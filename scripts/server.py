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

class QuickShareHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=web_dir, **kwargs)

    def end_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "*")
        self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
        super().end_headers()

    # --- File API: the web app cannot write to disk, so it asks this local server. ---

    def _origin_allowed(self):
        # Only the app itself (served from this server) may use the file API, not other websites.
        origin = self.headers.get("Origin")
        if not origin:
            return True
        port = self.server.server_address[1]
        return origin in (f"http://127.0.0.1:{port}", f"http://localhost:{port}")

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
        # Support single-page routing: fallback to index.html if file doesn't exist
        path = self.translate_path(self.path)
        if not os.path.exists(path) and "." not in os.path.basename(self.path):
            self.path = "/index.html"
        return super().do_GET()

    def log_message(self, format, *args):
        # Silent logging in background
        pass

class ReusableTCPServer(socketserver.TCPServer):
    allow_reuse_address = True

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
