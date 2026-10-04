import http.server
import socketserver
import sys
import os
import mimetypes
import json
import re
import subprocess
import shutil
import tarfile
import tempfile
import zipfile
import urllib.parse
import urllib.request
import urllib.error
import base64
import hashlib
import secrets
import struct
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

# =====================================================================================
# In-app updates for the packaged desktop app (web bundle + this launcher).
# Only release assets of this repository are accepted, and only after their SHA-256 matches.
# =====================================================================================
UPDATE_URL_PREFIX = "https://github.com/abhijeetmahakur/QuickShareStudio/releases/download/"
UPDATE_ALLOW_ANY_URL = os.environ.get("QUICKSHARE_UPDATE_ALLOW_ANY_URL") == "1"   # tests only
PACKAGED_FILES = ("server.py", "launch.ps1", "launch.vbs", "launch.sh", "app_icon.ico", "LICENSE", "VERSION")


def current_version():
    try:
        with open(os.path.join(script_dir, "VERSION"), encoding="utf-8") as f:
            return f.read().strip() or "0.0.0"
    except OSError:
        return "0.0.0"


UPDATE = {"state": "idle", "progress": 0.0, "error": None, "target": None}
UPDATE_LOCK = threading.Lock()


def is_packaged_install():
    """True when this launcher serves its own web/ folder (a release package), not a source checkout."""
    return os.path.realpath(web_dir) == os.path.realpath(os.path.join(script_dir, "web")) and \
        not os.path.isdir(os.path.join(script_dir, "..", "lib"))


def _set_update(**kw):
    with UPDATE_LOCK:
        UPDATE.update(kw)


def _package_root(folder):
    """The extracted folder that contains web/ and server.py."""
    for root, dirs, files in os.walk(folder):
        if "web" in dirs and "server.py" in files:
            return root
    return None


def apply_update(url, expected_sha256, version, restart=True):
    """Downloads, verifies, installs and restarts. Runs in a background thread."""
    work = tempfile.mkdtemp(prefix="quickshare_update_")
    try:
        _set_update(state="downloading", progress=0.0, error=None, target=version)
        archive = os.path.join(work, "package.zip" if url.endswith(".zip") else "package.tar.gz")
        digest = hashlib.sha256()
        req = urllib.request.Request(url, headers={"User-Agent": "QuickShareStudio-Updater"})
        with urllib.request.urlopen(req, timeout=60) as resp, open(archive, "wb") as out:
            total = int(resp.headers.get("Content-Length") or 0)
            done = 0
            while True:
                chunk = resp.read(1024 * 1024)
                if not chunk:
                    break
                out.write(chunk)
                digest.update(chunk)
                done += len(chunk)
                if total:
                    _set_update(progress=min(done / total, 1.0))
        _set_update(state="verifying", progress=1.0)
        if not secrets.compare_digest(digest.hexdigest(), expected_sha256.lower()):
            raise ValueError("The download was damaged (checksum mismatch). Nothing was changed.")

        _set_update(state="installing")
        extracted = os.path.join(work, "x")
        if archive.endswith(".zip"):
            with zipfile.ZipFile(archive) as z:
                for name in z.namelist():
                    target = os.path.realpath(os.path.join(extracted, name))
                    if not target.startswith(os.path.realpath(extracted)):
                        raise ValueError("The package contains unsafe paths.")
                z.extractall(extracted)
        else:
            with tarfile.open(archive) as t:
                for member in t.getmembers():
                    target = os.path.realpath(os.path.join(extracted, member.name))
                    if not target.startswith(os.path.realpath(extracted)) or member.issym() or member.islnk():
                        raise ValueError("The package contains unsafe paths.")
                t.extractall(extracted)
        root = _package_root(extracted)
        if not root:
            raise ValueError("The package does not look like QuickShare Studio.")

        # Swap web/ atomically-ish: keep the old copy until the new one is in place.
        old_web = os.path.join(script_dir, "web.old")
        shutil.rmtree(old_web, ignore_errors=True)
        live_web = os.path.join(script_dir, "web")
        os.replace(live_web, old_web)
        try:
            shutil.copytree(os.path.join(root, "web"), live_web)
        except Exception:
            shutil.rmtree(live_web, ignore_errors=True)
            os.replace(old_web, live_web)
            raise
        for name in PACKAGED_FILES:
            src = os.path.join(root, name)
            if os.path.isfile(src):
                shutil.copy2(src, os.path.join(script_dir, name))
        if not os.path.isfile(os.path.join(root, "VERSION")):
            with open(os.path.join(script_dir, "VERSION"), "w", encoding="utf-8") as f:
                f.write(version)
        shutil.rmtree(old_web, ignore_errors=True)
        _set_update(state="restarting")
        if restart:
            threading.Timer(0.8, restart_launcher).start()
        else:
            _set_update(state="done")
    except Exception as e:  # noqa: BLE001 - reported to the app
        message = str(e) if isinstance(e, ValueError) else f"The update could not be applied ({e.__class__.__name__})."
        _set_update(state="failed", error=message)
    finally:
        shutil.rmtree(work, ignore_errors=True)


SERVER_STATE = {"port": None}


def restart_launcher():
    """Starts the new launcher (it waits for our ports) and exits this one."""
    args = [sys.executable, os.path.join(script_dir, "server.py")]
    env = dict(os.environ, QUICKSHARE_PREFERRED_PORT=str(SERVER_STATE["port"] or ""))
    flags = 0x08000000 if sys.platform == "win32" else 0      # CREATE_NO_WINDOW
    subprocess.Popen(args, cwd=script_dir, env=env, close_fds=True, creationflags=flags)
    os._exit(0)


# Files being received in pieces (see QuickShareHandler._stream).
STREAMS = {}
STREAMS_LOCK = threading.Lock()

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
# LAN peer protocol (v2) - shared with the native apps (CrossDeviceTransferService).
#
#   UDP  8089  "QUICKSHARE_DISCOVER_V1"  -> JSON device info (who is on this Wi-Fi?)
#   HTTP 8088  GET  /api/ping, /api/device-info
#              POST /api/pair        {code,id,name,platform,port} -> {token,...} if code matches
#              GET  /api/v2/session?from=<peer id>   WebSocket upgrade (paired peers only)
#
# A v2 session carries QuickShare's transfer protocol (offer -> explicit accept -> chunks ->
# SHA-256), end-to-end encrypted by the app (X25519 + AES-GCM keyed with the pairing token).
# This server never sees file contents in clear: for the desktop app it only relays
# WebSocket frames between the page (loopback /api/lan/tunnel) and the other device.
#
# The LAN listener only exposes these endpoints. The file-saving / app API stays on the
# loopback server and is never reachable from other devices.
# =====================================================================================

PROTOCOL_VERSION = 2
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


# ----------------------------------------------------------------------------------------
# Minimal WebSocket (RFC 6455) support, stdlib only: enough to relay binary frames.
# ----------------------------------------------------------------------------------------
WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
WS_MAX_FRAME = 4 * 1024 * 1024
# Seconds the app has to pick up an incoming connection (overridable for tests).
TUNNEL_PICKUP_TIMEOUT = float(os.environ.get("QUICKSHARE_TUNNEL_TIMEOUT", "20"))


class WsClosed(Exception):
    pass


def ws_accept_key(key):
    return base64.b64encode(hashlib.sha1((key + WS_GUID).encode("ascii")).digest()).decode("ascii")


def _ws_mask(data, key):
    # XOR via big integers: orders of magnitude faster than a Python byte loop.
    n = len(data)
    if n == 0:
        return b""
    pad = (key * (n // 4 + 1))[:n]
    return (int.from_bytes(data, "big") ^ int.from_bytes(pad, "big")).to_bytes(n, "big")


class WsConn:
    """One WebSocket connection. [mask] is True for the client side (RFC 6455 5.3)."""

    def __init__(self, reader, sock, mask):
        self.reader = reader
        self.sock = sock
        self.mask = mask
        self.lock = threading.Lock()
        self.closed = False

    def _read(self, n):
        data = self.reader.read(n)
        if data is None or len(data) < n:
            raise WsClosed("connection closed")
        return data

    def recv(self):
        """Next data message as (opcode, payload). Answers pings; raises WsClosed at the end."""
        message, first = bytearray(), None
        while True:
            b0, b1 = self._read(2)
            fin, op = b0 & 0x80, b0 & 0x0F
            length = b1 & 0x7F
            if length == 126:
                length = struct.unpack(">H", self._read(2))[0]
            elif length == 127:
                length = struct.unpack(">Q", self._read(8))[0]
            if length > WS_MAX_FRAME:
                raise WsClosed("frame too large")
            key = self._read(4) if b1 & 0x80 else None
            data = self._read(length)
            if key:
                data = _ws_mask(data, key)
            if op == 0x8:
                self.close()
                raise WsClosed("closed by peer")
            if op == 0x9:
                self.send(data, opcode=0xA)
                continue
            if op == 0xA:
                continue
            if op in (0x1, 0x2):
                first, message = op, bytearray(data)
            elif op == 0x0 and first is not None:
                message += data
            if fin and first is not None:
                return first, bytes(message)

    def send(self, data, opcode=0x2):
        if self.closed:
            raise WsClosed("closed")
        n = len(data)
        header = bytearray([0x80 | opcode])
        bit = 0x80 if self.mask else 0
        if n < 126:
            header.append(bit | n)
        elif n < 65536:
            header.append(bit | 126)
            header += struct.pack(">H", n)
        else:
            header.append(bit | 127)
            header += struct.pack(">Q", n)
        if self.mask:
            key = os.urandom(4)
            header += key
            data = _ws_mask(data, key)
        with self.lock:
            self.sock.sendall(bytes(header) + data)

    def close(self):
        if self.closed:
            return
        try:
            with self.lock:
                frame = bytes([0x88, 0x80, 0, 0, 0, 0]) if self.mask else bytes([0x88, 0x00])
                self.sock.sendall(frame)
        except OSError:
            pass
        self.closed = True
        try:
            self.sock.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        try:
            self.sock.close()
        except OSError:
            pass


def ws_upgrade(handler):
    """Completes a server-side WebSocket upgrade on [handler]; returns a WsConn or None."""
    key = handler.headers.get("Sec-WebSocket-Key")
    if not key or handler.headers.get("Upgrade", "").lower() != "websocket":
        return None
    # Written by hand: WebSocket requires an HTTP/1.1 status line whatever the handler speaks.
    handler.wfile.write(
        b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
        + b"Sec-WebSocket-Accept: " + ws_accept_key(key).encode("ascii") + b"\r\n\r\n")
    handler.wfile.flush()
    handler.close_connection = True
    return WsConn(handler.rfile, handler.connection, mask=False)


def ws_connect(host, port, path, timeout=5):
    """Opens a client WebSocket to ws://host:port/path. Raises ConnectionError / PermissionError."""
    sock = socket.create_connection((host, port), timeout=timeout)
    try:
        key = base64.b64encode(os.urandom(16)).decode("ascii")
        sock.sendall((f"GET {path} HTTP/1.1\r\nHost: {host}:{port}\r\nUpgrade: websocket\r\n"
                      f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n").encode("ascii"))
        reader = sock.makefile("rb")
        status = reader.readline().decode("latin-1")
        headers = {}
        while True:
            line = reader.readline().decode("latin-1").strip()
            if not line:
                break
            name, _, value = line.partition(":")
            headers[name.strip().lower()] = value.strip()
        parts = status.split()
        code = int(parts[1]) if len(parts) > 1 and parts[1].isdigit() else 0
        if code == 401:
            raise PermissionError("not paired")
        if code != 101 or headers.get("sec-websocket-accept") != ws_accept_key(key):
            raise ConnectionError(f"upgrade refused (HTTP {code})")
        sock.settimeout(None)
        return WsConn(reader, sock, mask=True)
    except Exception:
        sock.close()
        raise


def ws_pump(src, dst):
    """Copies messages from src to dst until either side closes, then closes both."""
    try:
        while True:
            opcode, data = src.recv()
            dst.send(data, opcode=opcode)
    except (WsClosed, OSError, ValueError):
        pass
    finally:
        src.close()
        dst.close()


def ws_relay(a, b):
    """Relays both directions between two WebSockets; returns when the tunnel ends."""
    t = threading.Thread(target=ws_pump, args=(b, a), daemon=True)
    t.start()
    ws_pump(a, b)
    t.join(timeout=5)


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
        self.tunnels = {}                # tunnel id -> pending incoming session
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
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/api/ping":
            return self._json(200, {"status": "ok"})
        if parsed.path == "/api/device-info":
            return self._json(200, LAN.info())
        if parsed.path == "/api/v2/session":
            return self._session(urllib.parse.parse_qs(parsed.query))
        return self._json(404, {"error": "not found"})

    def _session(self, query):
        """A paired device opens an (end-to-end encrypted) transfer session with this PC."""
        peer_id = query.get("from", [""])[0]
        with LAN.lock:
            peer = LAN.peers.get(peer_id)
        if not peer:
            return self._json(401, {"error": "not paired with this device"})
        remote = ws_upgrade(self)
        if remote is None:
            return self._json(400, {"error": "websocket upgrade required"})
        tunnel_id = uuid.uuid4().hex
        pending = {"ws": remote, "ready": threading.Event(), "app": None}
        with LAN.lock:
            LAN.tunnels[tunnel_id] = pending
        LAN.add_event({"type": "tunnel_incoming", "tunnelId": tunnel_id, "peer": _peer_public(peer)})
        picked_up = pending["ready"].wait(TUNNEL_PICKUP_TIMEOUT)
        with LAN.lock:
            LAN.tunnels.pop(tunnel_id, None)
        if not picked_up or pending["app"] is None:
            remote.close()
            return None
        ws_pump(remote, pending["app"])
        return None

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
        # Protocol v1 sent files without asking the receiver and without encryption.
        return self._json(426, {"error": "This device runs QuickShare 2. Update QuickShare on the sending device."})


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

    def _lan_tunnel(self, query):
        """Relays an encrypted session between the app (this WebSocket) and another device."""
        accept_id = query.get("accept", [""])[0]
        if accept_id:
            with LAN.lock:
                pending = LAN.tunnels.get(accept_id)
            if not pending or pending["ready"].is_set():
                return self._send_json(404, {"error": "that connection is gone"})
            app = ws_upgrade(self)
            if app is None:
                return self._send_json(400, {"error": "websocket upgrade required"})
            pending["app"] = app
            pending["ready"].set()
            # The LAN handler thread pumps device -> app; this one pumps app -> device.
            ws_pump(app, pending["ws"])
            return None
        peer_id = query.get("peer", [""])[0]
        with LAN.lock:
            peer = LAN.peers.get(peer_id)
        if not peer:
            return self._send_json(404, {"error": "This device is not paired. Pair again from Device Pairing."})
        try:
            remote = ws_connect(peer["ip"], peer["port"],
                                "/api/v2/session?" + urllib.parse.urlencode({"from": LAN.device_id}))
        except PermissionError:
            return self._send_json(401, {"error": f'"{peer["name"]}" no longer recognises this PC. Pair again.'})
        except (OSError, ConnectionError, ValueError):
            return self._send_json(502, {"error": f'Could not reach "{peer["name"]}". Make sure it is on the same Wi-Fi and QuickShare is open.'})
        app = ws_upgrade(self)
        if app is None:
            remote.close()
            return self._send_json(400, {"error": "websocket upgrade required"})
        ws_relay(app, remote)
        return None

    def _update_get(self):
        with UPDATE_LOCK:
            state = dict(UPDATE)
        return self._send_json(200, {**state, "version": current_version(), "packaged": is_packaged_install(),
                                     "pid": os.getpid()})

    def _update_post(self):
        data = self._read_json()
        url = str(data.get("url") or "")
        sha = str(data.get("sha256") or "").lower()
        version = str(data.get("version") or "")
        if not is_packaged_install():
            return self._send_json(501, {"error": "This copy runs from the source code. Update it with git pull and a rebuild."})
        if not (UPDATE_ALLOW_ANY_URL or url.startswith(UPDATE_URL_PREFIX)) or not (url.endswith(".zip") or url.endswith(".tar.gz")):
            return self._send_json(400, {"error": "Updates are only accepted from QuickShare Studio's GitHub releases."})
        if not re.fullmatch(r"[0-9a-f]{64}", sha):
            return self._send_json(400, {"error": "The release has no SHA-256 checksum, so it cannot be verified."})
        with UPDATE_LOCK:
            busy = UPDATE["state"] in ("downloading", "verifying", "installing", "restarting")
        if busy:
            return self._send_json(409, {"error": "An update is already in progress."})
        threading.Thread(target=apply_update, args=(url, sha, version), daemon=True).start()
        return self._send_json(200, {"ok": True})

    def _lan_get(self, path, query):
        if path == "/api/update/status":
            return self._update_get()
        if path == "/api/lan/tunnel":
            return self._lan_tunnel(query)
        if path == "/api/lan/status":
            return self._send_json(200, {
                **LAN.info(), "available": LAN.port is not None,
                "discovery": LAN.discovery_ok, "error": LAN.error,
            })
        if path == "/api/lan/peers":
            # Tokens are the pre-shared keys the app needs for end-to-end encryption. This API
            # is loopback-only and origin-checked, so only the app itself can read them.
            with LAN.lock:
                peers = [{**_peer_public(p), "token": p["token"]} for p in LAN.peers.values()]
            return self._send_json(200, {"peers": peers})
        if path == "/api/lan/events":
            since = int(query.get("since", ["0"])[0] or 0)
            with LAN.lock:
                events = [e for e in LAN.events if e["seq"] > since]
                seq = LAN.seq
            return self._send_json(200, {"seq": seq, "events": events})
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

    def _target_dir(self, query):
        custom_dir = query.get("dir", [""])[0].strip()
        return custom_dir if custom_dir and os.path.isabs(custom_dir) else default_save_dir()

    def _stream(self, path, query):
        """Receives a file in pieces: open -> append... -> commit (or discard)."""
        if path == "/api/stream/open":
            name = sanitize_filename(query.get("name", ["file"])[0])
            folder = self._target_dir(query)
            os.makedirs(folder, exist_ok=True)
            stream_id = uuid.uuid4().hex
            part = os.path.join(folder, f".quickshare-{stream_id}.part")
            open(part, "wb").close()
            with STREAMS_LOCK:
                STREAMS[stream_id] = {"part": part, "folder": folder, "name": name, "size": 0}
            return self._send_json(200, {"id": stream_id})
        with STREAMS_LOCK:
            entry = STREAMS.get(query.get("id", [""])[0])
        if not entry:
            return self._send_json(404, {"error": "unknown stream"})
        if path == "/api/stream/append":
            length = int(self.headers.get("Content-Length", "0"))
            data = self.rfile.read(length)
            with open(entry["part"], "ab") as f:
                f.write(data)
            entry["size"] += len(data)
            return self._send_json(200, {"size": entry["size"]})
        if path == "/api/stream/commit":
            target = unique_path(os.path.join(entry["folder"], entry["name"]))
            os.replace(entry["part"], target)
            with STREAMS_LOCK:
                STREAMS.pop(query.get("id", [""])[0], None)
            WRITTEN_FILES.add(os.path.realpath(target).lower())
            return self._send_json(200, {"path": target, "size": entry["size"]})
        if path == "/api/stream/discard":
            try:
                os.remove(entry["part"])
            except OSError:
                pass
            with STREAMS_LOCK:
                STREAMS.pop(query.get("id", [""])[0], None)
            return self._send_json(200, {"ok": True})
        return self._send_json(404, {"error": "not found"})

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
            if parsed.path.startswith("/api/stream/"):
                return self._stream(parsed.path, query)
            if parsed.path == "/api/update/apply":
                return self._update_post()
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

def _bind_preferred(port, attempts=60):
    """After an update the new launcher waits for the old one to release its port."""
    for _ in range(attempts):
        try:
            return ReusableTCPServer(("127.0.0.1", port), QuickShareHandler)
        except OSError:
            time.sleep(0.25)
    return None


def run():
    starting_port = 52830
    port_file = os.path.join(script_dir, "active_port.txt")
    
    server = None
    selected_port = None

    preferred = os.environ.get("QUICKSHARE_PREFERRED_PORT", "")
    if preferred.isdigit():
        server = _bind_preferred(int(preferred))
        if server:
            selected_port = int(preferred)

    for port in range(starting_port, starting_port + 100):
        if server:
            break
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

    SERVER_STATE["port"] = selected_port
    if os.environ.get("QUICKSHARE_NO_LAN") != "1":
        if preferred.isdigit():
            # Keep the LAN port paired devices know: wait for the previous launcher to exit.
            for _ in range(40):
                try:
                    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
                        probe.bind(("0.0.0.0", LAN_HTTP_PORT))
                    break
                except OSError:
                    time.sleep(0.25)
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
