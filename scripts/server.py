import http.server
import socketserver
import sys
import os
import mimetypes
import json
import re
import subprocess
import tempfile
import urllib.parse
import urllib.request
import urllib.error
import hashlib
import secrets
import socket
import threading
import time
import uuid
import platform as _platform

# Set directory
script_dir = os.path.dirname(os.path.abspath(__file__))
web_dir = os.path.join(script_dir, "web")
if len(sys.argv) > 1 and os.path.isdir(sys.argv[1]):
    web_dir = sys.argv[1]
elif not os.path.isdir(web_dir):
    parent_web = os.path.join(os.path.dirname(script_dir), "build", "web")
    if os.path.isdir(parent_web):
        web_dir = parent_web

mimetypes.init()
mimetypes.add_type("application/wasm", ".wasm")
mimetypes.add_type("application/javascript", ".js")
mimetypes.add_type("application/javascript", ".mjs")
mimetypes.add_type("application/json", ".json")


def default_save_dir():
    return os.path.join(os.path.expanduser("~"), "Downloads", "QuickShare")


def open_with_default_app(path):
    if sys.platform == "win32":
        os.startfile(path)
    elif sys.platform == "darwin":
        subprocess.Popen(["open", path])
    else:
        subprocess.Popen(["xdg-open", path])


def reveal_in_file_manager(path):
    if sys.platform == "win32":
        subprocess.Popen(["explorer", "/select,", path])
    elif sys.platform == "darwin":
        subprocess.Popen(["open", "-R", path])
    else:
        # Most Linux file managers cannot select a file, so open its folder.
        subprocess.Popen(["xdg-open", os.path.dirname(path)])


def preview_dir():
    return os.path.join(tempfile.gettempdir(), "QuickSharePreview")


def sanitize_filename(name):
    name = os.path.basename(name.replace("\\", "/")).strip()
    name = re.sub(r'[<>:"/\\|?*\x00-\x1f]', "_", name).strip(" .")
    if not name:
        name = "document.pdf"
    return name


# Files this server wrote during this run (may live in a custom download folder).
WRITTEN_FILES = set()

# Received files can come from other devices; never launch anything that runs code.
BLOCKED_OPEN_EXTENSIONS = {
    ".exe", ".bat", ".cmd", ".com", ".msi", ".msp", ".scr", ".pif", ".cpl", ".ps1", ".psm1",
    ".vbs", ".vbe", ".js", ".jse", ".wsf", ".wsh", ".hta", ".lnk", ".url", ".jar", ".reg",
    ".dll", ".sys", ".appx", ".msix", ".application", ".gadget", ".inf", ".scf",
}


def unique_path(path):
    # Never overwrite an earlier export: "Report.pdf" -> "Report (2).pdf".
    if not os.path.exists(path):
        return path
    stem, ext = os.path.splitext(path)
    n = 2
    while os.path.exists(f"{stem} ({n}){ext}"):
        n += 1
    return f"{stem} ({n}){ext}"

# =====================================================================================
# LAN peer protocol (v1) — shared with the native apps (CrossDeviceTransferService).
#
#   UDP  8089  "QUICKSHARE_DISCOVER_V1"  -> JSON device info (who is on this Wi-Fi?)
#   HTTP 8088  GET  /api/ping, /api/device-info
#              POST /api/pair      {code,id,name,platform,port} -> {token,...} if code matches
#              POST /api/transfer  file body; requires x-sender-id + x-pair-token from pairing
#
# The LAN listener only exposes these endpoints. The file-saving / app API stays on the
# loopback server and is never reachable from other devices.
# =====================================================================================

PROTOCOL_VERSION = 1
# Overridable for running two instances on one machine (tests); real devices use the defaults.
LAN_HTTP_PORT = int(os.environ.get("QUICKSHARE_LAN_PORT", "8088"))
DISCOVERY_PORT = int(os.environ.get("QUICKSHARE_DISCOVERY_PORT", "8089"))
DISCOVER_MESSAGE = b"QUICKSHARE_DISCOVER_V1"
MAX_TRANSFER_BYTES = 4 * 1024 * 1024 * 1024
PAIR_FAILURE_LIMIT = 8          # wrong codes allowed per IP ...
PAIR_FAILURE_WINDOW = 300       # ... per 5 minutes


def _platform_name():
    return {"win32": "Windows", "darwin": "macOS"}.get(sys.platform, "Linux")


def detect_lan_ip():
    """IPv4 address other devices on the same network can reach (no packets are sent)."""
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("10.255.255.255", 1))
            ip = s.getsockname()[0]
            if not ip.startswith("127."):
                return ip
    except OSError:
        pass
    try:
        return socket.gethostbyname(socket.gethostname())
    except OSError:
        return "127.0.0.1"


class LanState:
    def __init__(self):
        self.lock = threading.Lock()
        self.device_id = "pc-" + uuid.uuid4().hex[:12]
        self.device_name = _platform.node() or "QuickShare PC"
        self.code = None                 # current 6-digit pairing code (set by the app)
        self.ip = detect_lan_ip()
        self.port = None                 # LAN HTTP port actually bound
        self.discovery_ok = False
        self.error = None
        self.peers = {}                  # peer id -> {id,name,platform,ip,port,token}
        self.events = []                 # [{seq, type, ...}] for the app to poll
        self.seq = 0
        self.received = {}               # file id -> absolute path
        self.failures = {}               # ip -> [timestamps of wrong codes]

    def info(self):
        return {
            "id": self.device_id, "name": self.device_name, "platform": _platform_name(),
            "ip": self.ip, "port": self.port, "protocol": PROTOCOL_VERSION,
        }

    def add_event(self, event):
        with self.lock:
            self.seq += 1
            event["seq"] = self.seq
            self.events.append(event)
            del self.events[:-500]       # keep the most recent events only

    def remember_peer(self, peer):
        with self.lock:
            self.peers[peer["id"]] = peer


LAN = LanState()


def _peer_public(peer):
    return {k: peer[k] for k in ("id", "name", "platform", "ip", "port")}


class LanPeerHandler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, format, *args):
        pass

    def _json(self, status, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/api/ping":
            return self._json(200, {"status": "ok"})
        if self.path == "/api/device-info":
            return self._json(200, LAN.info())
        return self._json(404, {"error": "not found"})

    def do_POST(self):
        if self.path == "/api/pair":
            return self._pair()
        if self.path == "/api/transfer":
            return self._transfer()
        return self._json(404, {"error": "not found"})

    def _pair(self):
        ip = self.client_address[0]
        now = time.time()
        with LAN.lock:
            recent = [t for t in LAN.failures.get(ip, []) if now - t < PAIR_FAILURE_WINDOW]
            LAN.failures[ip] = recent
            limited = len(recent) >= PAIR_FAILURE_LIMIT
        if limited:
            return self._json(429, {"error": "too many wrong codes, try again in a few minutes"})
        try:
            length = int(self.headers.get("Content-Length", "0"))
            data = json.loads(self.rfile.read(min(length, 16384)) or b"{}")
        except (ValueError, json.JSONDecodeError):
            return self._json(400, {"error": "bad request"})
        code = re.sub(r"\D", "", str(data.get("code", "")))
        if not LAN.code or not secrets.compare_digest(code, LAN.code):
            with LAN.lock:
                LAN.failures.setdefault(ip, []).append(now)
            return self._json(403, {"error": "wrong or expired code"})
        token = secrets.token_hex(16)
        peer = {
            "id": str(data.get("id") or ("peer-" + uuid.uuid4().hex[:8]))[:64],
            "name": str(data.get("name") or "Device")[:80],
            "platform": str(data.get("platform") or "Device")[:32],
            "ip": ip,                                   # the address it actually came from
            "port": int(data.get("port") or LAN_HTTP_PORT),
            "token": token,
        }
        LAN.remember_peer(peer)
        LAN.add_event({"type": "peer_paired", "device": _peer_public(peer)})
        return self._json(200, {**LAN.info(), "status": "paired", "token": token})

    def _transfer(self):
        sender_id = self.headers.get("x-sender-id", "")
        token = self.headers.get("x-pair-token", "")
        with LAN.lock:
            peer = LAN.peers.get(sender_id)
        if not peer or not token or not secrets.compare_digest(token, peer["token"]):
            return self._json(401, {"error": "not paired with this device"})
        try:
            length = int(self.headers.get("Content-Length", "-1"))
        except ValueError:
            length = -1
        if length < 0 or length > MAX_TRANSFER_BYTES:
            return self._json(411 if length < 0 else 413, {"error": "missing or too large Content-Length"})

        name = sanitize_filename(urllib.parse.unquote(self.headers.get("x-file-name", "Received_File")))
        expected = (self.headers.get("x-sha256") or "").lower()
        os.makedirs(default_save_dir(), exist_ok=True)
        target = unique_path(os.path.join(default_save_dir(), name))
        digest = hashlib.sha256()
        remaining = length
        try:
            with open(target, "wb") as f:
                while remaining > 0:
                    chunk = self.rfile.read(min(remaining, 1024 * 1024))
                    if not chunk:
                        raise ConnectionError("connection closed early")
                    digest.update(chunk)
                    f.write(chunk)
                    remaining -= len(chunk)
        except Exception as e:  # noqa: BLE001 - reported to the sender
            try:
                os.remove(target)
            except OSError:
                pass
            return self._json(400, {"error": f"transfer interrupted: {e}"})
        sha = digest.hexdigest()
        if expected and expected != sha:
            os.remove(target)
            return self._json(400, {"error": "checksum mismatch"})

        file_id = uuid.uuid4().hex
        with LAN.lock:
            LAN.received[file_id] = target
        WRITTEN_FILES.add(os.path.realpath(target).lower())
        LAN.add_event({
            "type": "file_received", "fileId": file_id, "fileName": os.path.basename(target),
            "size": length, "sha256": sha, "path": target,
            "sender": _peer_public(peer),
        })
        return self._json(200, {"status": "success", "fileName": name, "bytesReceived": length, "sha256": sha})


class ThreadingHTTPServerExclusive(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    # On Windows SO_REUSEADDR lets a second process take over a port that is in use.
    allow_reuse_address = sys.platform != "win32"


def start_lan_services(http_ports=range(LAN_HTTP_PORT, LAN_HTTP_PORT + 10), discovery_port=DISCOVERY_PORT):
    """Starts the LAN HTTP listener and the UDP discovery responder."""
    for port in http_ports:
        try:
            server = ThreadingHTTPServerExclusive(("0.0.0.0", port), LanPeerHandler)
        except OSError:
            continue
        LAN.port = port
        threading.Thread(target=server.serve_forever, daemon=True).start()
        break
    else:
        LAN.error = "no free LAN port between 8088 and 8097"
        return

    def discovery_responder():
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            if sys.platform != "win32":
                sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            sock.bind(("", discovery_port))
        except OSError as e:
            LAN.error = f"discovery unavailable: {e}"
            return
        LAN.discovery_ok = True
        while True:
            try:
                data, addr = sock.recvfrom(2048)
                if data.strip() == DISCOVER_MESSAGE:
                    sock.sendto(json.dumps(LAN.info()).encode("utf-8"), addr)
            except OSError:
                time.sleep(0.2)

    threading.Thread(target=discovery_responder, daemon=True).start()


def discover_devices(timeout=1.5, discovery_port=DISCOVERY_PORT):
    """Broadcasts a discovery request and returns the devices that answered."""
    found = {}
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        sock.bind(("", 0))
        sock.settimeout(0.25)
        targets = {"255.255.255.255", "127.0.0.1"}
        parts = LAN.ip.split(".")
        if len(parts) == 4:
            targets.add(".".join(parts[:3] + ["255"]))   # common /24 subnet broadcast
        for target in targets:
            try:
                sock.sendto(DISCOVER_MESSAGE, (target, discovery_port))
            except OSError:
                pass
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                data, addr = sock.recvfrom(4096)
            except socket.timeout:
                continue
            except OSError:
                break
            try:
                info = json.loads(data)
            except json.JSONDecodeError:
                continue
            if info.get("id") == LAN.device_id:
                continue
            if not addr[0].startswith("127."):
                info["ip"] = addr[0]
            found[info.get("id")] = info
    return list(found.values())


def _http_json(url, payload=None, timeout=5):
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"},
                                 method="POST" if data is not None else "GET")
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read() or b"{}")


def pair_direct(ip, port, code):
    """Pairs with the device at ip:port using its code. Returns the peer, or raises."""
    try:
        reply = _http_json(f"http://{ip}:{port}/api/pair", {
            "code": code, "id": LAN.device_id, "name": LAN.device_name,
            "platform": _platform_name(), "port": LAN.port,
        })
    except urllib.error.HTTPError as e:
        if e.code == 403:
            raise ValueError("That code is wrong or has expired.")
        if e.code == 429:
            raise ValueError("Too many wrong codes. Wait a few minutes and try again.")
        raise ValueError(f"The device refused pairing (HTTP {e.code}).")
    except (urllib.error.URLError, OSError) as e:
        raise ConnectionError(f"Could not reach {ip}:{port} ({e}).")
    peer = {
        "id": reply.get("id") or f"{ip}:{port}", "name": reply.get("name") or "Device",
        "platform": reply.get("platform") or "Device", "ip": ip,
        "port": int(reply.get("port") or port), "token": reply["token"],
    }
    LAN.remember_peer(peer)
    return peer


def pair_by_code(code, discovery_port=DISCOVERY_PORT):
    """Finds the device on this network that is showing [code] and pairs with it."""
    devices = discover_devices(discovery_port=discovery_port)
    if not devices:
        raise LookupError("No QuickShare devices answered on this network. "
                          "Check that both devices are on the same Wi-Fi and the app is open.")
    result = []

    def attempt(info):
        try:
            result.append(pair_direct(info["ip"], int(info.get("port") or LAN_HTTP_PORT), code))
        except Exception:  # noqa: BLE001 - only the matching device succeeds
            pass

    threads = [threading.Thread(target=attempt, args=(d,)) for d in devices]
    for t in threads:
        t.start()
    for t in threads:
        t.join(timeout=8)
    if result:
        return result[0]
    raise LookupError("No device on this network is showing that code. Check the code and try again.")


def send_to_peer(peer_id, file_name, data):
    with LAN.lock:
        peer = LAN.peers.get(peer_id)
    if not peer:
        raise LookupError("This device is not paired. Pair again from Device Pairing.")
    sha = hashlib.sha256(data).hexdigest()
    req = urllib.request.Request(
        f"http://{peer['ip']}:{peer['port']}/api/transfer", data=data, method="POST",
        headers={
            "Content-Type": "application/octet-stream",
            "x-file-name": urllib.parse.quote(file_name),
            "x-file-size": str(len(data)),
            "x-sender-id": LAN.device_id,
            "x-sender-name": urllib.parse.quote(LAN.device_name),
            "x-sender-platform": _platform_name(),
            "x-pair-token": peer["token"],
            "x-sha256": sha,
        })
    timeout = 30 + len(data) / (256 * 1024)      # allow ~256 KB/s minimum throughput
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            reply = json.loads(resp.read() or b"{}")
    except urllib.error.HTTPError as e:
        if e.code == 401:
            raise PermissionError(f'"{peer["name"]}" no longer recognises this PC. Pair again.')
        raise ConnectionError(f'"{peer["name"]}" rejected the file (HTTP {e.code}).')
    except (urllib.error.URLError, OSError):
        raise ConnectionError(f'Could not reach "{peer["name"]}" at {peer["ip"]}:{peer["port"]}. '
                              "Make sure it is on the same Wi-Fi and QuickShare is open.")
    return {"status": "sent", "sha256": sha, "reply": reply}


class QuickShareHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=web_dir, **kwargs)

    def end_headers(self):
        if not self.path.startswith("/api/"):
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
            self.send_header("Access-Control-Allow-Headers", "*")
        self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
        super().end_headers()

    # --- File API: the web app cannot write to disk, so it asks this local server. ---

    def _origin_allowed(self):
        # Only the app itself (served from this server) may use the API, not other websites.
        # The Host check also stops DNS-rebinding pages from posing as localhost.
        port = self.server.server_address[1]
        allowed = (f"127.0.0.1:{port}", f"localhost:{port}")
        if self.headers.get("Host", "") not in allowed:
            return False
        origin = self.headers.get("Origin")
        return not origin or origin in tuple("http://" + a for a in allowed)

    def _read_json(self):
        length = int(self.headers.get("Content-Length", "0"))
        return json.loads(self.rfile.read(length) or b"{}")

    # --- LAN bridge API used by the app (pairing, sending, receiving) ---

    def _lan_get(self, path, query):
        if path == "/api/lan/status":
            return self._send_json(200, {
                **LAN.info(), "available": LAN.port is not None,
                "discovery": LAN.discovery_ok, "error": LAN.error,
            })
        if path == "/api/lan/peers":
            with LAN.lock:
                peers = [_peer_public(p) for p in LAN.peers.values()]
            return self._send_json(200, {"peers": peers})
        if path == "/api/lan/events":
            since = int(query.get("since", ["0"])[0] or 0)
            with LAN.lock:
                events = [e for e in LAN.events if e["seq"] > since]
                seq = LAN.seq
            return self._send_json(200, {"seq": seq, "events": events})
        if path == "/api/lan/file":
            with LAN.lock:
                target = LAN.received.get(query.get("id", [""])[0])
            if not target or not os.path.isfile(target):
                return self._send_json(404, {"error": "file not found"})
            with open(target, "rb") as f:
                data = f.read()
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return None
        return self._send_json(404, {"error": "not found"})

    def _lan_post(self, path, query):
        if path == "/api/lan/session":
            data = self._read_json()
            code = re.sub(r"\D", "", str(data.get("code") or ""))
            with LAN.lock:
                LAN.code = code if len(code) == 6 else None
                if data.get("deviceId"):
                    LAN.device_id = str(data["deviceId"])[:64]
                if data.get("deviceName"):
                    LAN.device_name = str(data["deviceName"])[:80]
            return self._send_json(200, {"ok": True})
        if path in ("/api/lan/pair", "/api/lan/pair-direct"):
            data = self._read_json()
            code = re.sub(r"\D", "", str(data.get("code") or ""))
            if len(code) != 6:
                return self._send_json(400, {"error": "Enter the 6-digit code shown on the other device."})
            if LAN.code and code == LAN.code:
                return self._send_json(400, {"error": "That is this computer's own code. Enter the code from the other device."})
            try:
                if path == "/api/lan/pair":
                    peer = pair_by_code(code)
                else:
                    peer = pair_direct(str(data["ip"]), int(data.get("port") or LAN_HTTP_PORT), code)
            except (LookupError, ValueError, ConnectionError, KeyError) as e:
                return self._send_json(404, {"error": str(e)})
            LAN.add_event({"type": "peer_paired", "device": _peer_public(peer)})
            return self._send_json(200, {"device": _peer_public(peer)})
        if path == "/api/lan/send":
            length = int(self.headers.get("Content-Length", "0"))
            data = self.rfile.read(length)
            name = sanitize_filename(query.get("name", ["file"])[0])
            try:
                result = send_to_peer(query.get("peer", [""])[0], name, data)
            except (LookupError, PermissionError, ConnectionError) as e:
                return self._send_json(502, {"error": str(e)})
            return self._send_json(200, result)
        if path == "/api/lan/unpair":
            data = self._read_json()
            with LAN.lock:
                LAN.peers.pop(str(data.get("peer", "")), None)
            return self._send_json(200, {"ok": True})
        return self._send_json(404, {"error": "not found"})

    def _send_json(self, status, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _resolve_saved_file(self, query):
        # Opening/revealing is limited to existing files inside the save/preview folders.
        path = os.path.realpath(query.get("path", [""])[0])
        if not os.path.isfile(path):
            return None
        if path.lower() in WRITTEN_FILES:
            return path
        for root in (default_save_dir(), preview_dir()):
            root = os.path.realpath(root).lower()
            if os.path.commonpath([path.lower(), root]) == root:
                return path
        return None

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        query = urllib.parse.parse_qs(parsed.query)
        if not parsed.path.startswith("/api/"):
            return self._send_json(404, {"error": "not found"})
        if not self._origin_allowed():
            return self._send_json(403, {"error": "forbidden origin"})

        try:
            if parsed.path.startswith("/api/lan/"):
                return self._lan_post(parsed.path, query)
            if parsed.path == "/api/save-file":
                length = int(self.headers.get("Content-Length", "0"))
                data = self.rfile.read(length)
                name = sanitize_filename(query.get("name", ["document.pdf"])[0])
                # Preview copies go to a temp folder and are overwritten, so printing
                # does not pile up files in Downloads\QuickShare.
                preview = query.get("preview", ["0"])[0] == "1"
                # Optional absolute folder chosen in Settings → Download folder.
                custom_dir = query.get("dir", [""])[0].strip()
                if preview:
                    save_dir = preview_dir()
                elif custom_dir and os.path.isabs(custom_dir):
                    save_dir = custom_dir
                else:
                    save_dir = default_save_dir()
                os.makedirs(save_dir, exist_ok=True)
                target = os.path.join(save_dir, name)
                if not preview:
                    target = unique_path(target)
                with open(target, "wb") as f:
                    f.write(data)
                WRITTEN_FILES.add(os.path.realpath(target).lower())
                return self._send_json(200, {"path": target})

            if parsed.path in ("/api/open-file", "/api/reveal-file"):
                path = self._resolve_saved_file(query)
                if not path:
                    return self._send_json(400, {"error": "invalid path"})
                blocked = os.path.splitext(path)[1].lower() in BLOCKED_OPEN_EXTENSIONS
                if parsed.path == "/api/open-file" and not blocked:
                    open_with_default_app(path)
                else:
                    reveal_in_file_manager(path)
                return self._send_json(200, {"path": path})
        except Exception as e:
            return self._send_json(500, {"error": str(e)})

        return self._send_json(404, {"error": "not found"})

    def do_OPTIONS(self):
        self.send_response(204)
        self.end_headers()

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path.startswith("/api/"):
            if not self._origin_allowed():
                return self._send_json(403, {"error": "forbidden origin"})
            try:
                return self._lan_get(parsed.path, urllib.parse.parse_qs(parsed.query))
            except Exception as e:  # noqa: BLE001
                return self._send_json(500, {"error": str(e)})
        # Support single-page routing: fallback to index.html if file doesn't exist
        path = self.translate_path(self.path)
        if not os.path.exists(path) and "." not in os.path.basename(self.path):
            self.path = "/index.html"
        return super().do_GET()

    def log_message(self, format, *args):
        # Silent logging in background
        pass

class ReusableTCPServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    daemon_threads = True
    # On Windows SO_REUSEADDR would let two app instances bind the same port.
    allow_reuse_address = sys.platform != "win32"

def run():
    starting_port = 52830
    port_file = os.path.join(script_dir, "active_port.txt")
    
    server = None
    selected_port = None

    for port in range(starting_port, starting_port + 100):
        try:
            server = ReusableTCPServer(("127.0.0.1", port), QuickShareHandler)
            selected_port = port
            break
        except OSError:
            continue

    if not server:
        for port in range(8080, 8150):
            try:
                server = ReusableTCPServer(("127.0.0.1", port), QuickShareHandler)
                selected_port = port
                break
            except OSError:
                continue

    if not server or not selected_port:
        sys.exit(1)

    try:
        with open(port_file, "w") as f:
            f.write(str(selected_port))
    except Exception:
        pass

    if os.environ.get("QUICKSHARE_NO_LAN") != "1":
        start_lan_services()

    try:
        server.serve_forever()
    finally:
        try:
            if os.path.exists(port_file):
                os.remove(port_file)
        except Exception:
            pass

if __name__ == "__main__":
    run()
