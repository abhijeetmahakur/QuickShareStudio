"""End-to-end test of the LAN peer protocol (v2) in scripts/server.py.

Starts two independent server instances ("PC A" and "PC B") on one machine and checks
discovery, code pairing, the encrypted-session tunnel in both directions, streaming saves,
and the security rules.

    python test/lan/test_lan_protocol.py
"""
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SERVER = os.path.join(ROOT, "scripts", "server.py")

# Reuse the server's own WebSocket client to play the part of the app.
_spec = importlib.util.spec_from_file_location("qs_server", SERVER)
qs = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(qs)


class Instance:
    """One copy of server.py in its own folder (so each writes its own port file)."""

    def __init__(self, lan_port, discovery_port, downloads):
        self.dir = tempfile.mkdtemp(prefix="qs_lan_")
        shutil.copy(SERVER, self.dir)
        os.makedirs(os.path.join(self.dir, "web"))
        with open(os.path.join(self.dir, "web", "index.html"), "w") as f:
            f.write("<html></html>")
        env = dict(os.environ, QUICKSHARE_LAN_PORT=str(lan_port),
                   QUICKSHARE_DISCOVERY_PORT=str(discovery_port),
                   QUICKSHARE_TUNNEL_TIMEOUT="3",
                   HOME=downloads, USERPROFILE=downloads)
        self.proc = subprocess.Popen([sys.executable, os.path.join(self.dir, "server.py")],
                                     cwd=self.dir, env=env)
        port_file = os.path.join(self.dir, "active_port.txt")
        for _ in range(100):
            if os.path.exists(port_file) and open(port_file).read().strip():
                break
            time.sleep(0.1)
        self.app_port = int(open(port_file).read().strip())
        self.lan_port = lan_port
        for _ in range(50):          # wait until the LAN listener is up
            try:
                if self.get("/api/lan/status")["available"]:
                    break
            except Exception:
                pass
            time.sleep(0.1)

    def _request(self, path, data=None, headers=None, method=None):
        url = f"http://127.0.0.1:{self.app_port}{path}"
        req = urllib.request.Request(url, data=data, method=method or ("POST" if data is not None else "GET"),
                                     headers={"Host": f"127.0.0.1:{self.app_port}", **(headers or {})})
        with urllib.request.urlopen(req, timeout=20) as resp:
            body = resp.read()
            return body if resp.headers.get("Content-Type") == "application/octet-stream" else json.loads(body)

    def get(self, path, **kw):
        return self._request(path, **kw)

    def post_json(self, path, payload):
        return self._request(path, json.dumps(payload).encode(), {"Content-Type": "application/json"})

    def events(self, kind):
        return [e for e in self.get("/api/lan/events?since=0")["events"] if e["type"] == kind]

    def app_socket(self, query):
        """The app's WebSocket to its own server (loopback tunnel API)."""
        return qs.ws_connect("127.0.0.1", self.app_port, "/api/lan/tunnel?" + query)

    def stop(self):
        self.proc.terminate()
        self.proc.wait(timeout=10)
        shutil.rmtree(self.dir, ignore_errors=True)


def status_of(fn):
    try:
        fn()
        return 200
    except urllib.error.HTTPError as e:
        return e.code


class LanProtocolTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.downloads = tempfile.mkdtemp(prefix="qs_home_")
        # A answers discovery on 18089; B cannot bind the same port and only searches.
        cls.a = Instance(18088, 18089, cls.downloads)
        cls.b = Instance(18188, 18089, cls.downloads)
        cls.a.post_json("/api/lan/session", {"code": "123456", "deviceId": "pc-a", "deviceName": "PC A"})
        cls.b.post_json("/api/lan/session", {"code": "654321", "deviceId": "pc-b", "deviceName": "PC B"})

    @classmethod
    def tearDownClass(cls):
        cls.a.stop()
        cls.b.stop()
        shutil.rmtree(cls.downloads, ignore_errors=True)

    def test_1_status(self):
        status = self.a.get("/api/lan/status")
        self.assertTrue(status["available"])
        self.assertEqual(status["port"], 18088)
        self.assertEqual(status["protocol"], 2)

    def test_2_wrong_code_is_rejected(self):
        code = status_of(lambda: self.b.post_json("/api/lan/pair", {"code": "000000"}))
        self.assertEqual(code, 404)

    def test_3_own_code_is_rejected(self):
        code = status_of(lambda: self.b.post_json("/api/lan/pair", {"code": "654321"}))
        self.assertEqual(code, 400)

    def test_4_pair_then_tunnel_both_ways(self):
        paired = self.b.post_json("/api/lan/pair", {"code": "123456"})["device"]
        self.assertEqual(paired["id"], "pc-a")
        self.assertEqual(paired["name"], "PC A")
        # A learned about B through the pairing request; both apps get the shared token.
        self.assertTrue(any(e["device"]["id"] == "pc-b" for e in self.a.events("peer_paired")))
        token_b = {p["id"]: p for p in self.b.get("/api/lan/peers")["peers"]}["pc-a"]["token"]
        token_a = {p["id"]: p for p in self.a.get("/api/lan/peers")["peers"]}["pc-b"]["token"]
        self.assertEqual(token_a, token_b)
        self.assertEqual(len(token_a), 32)

        before = len(self.a.events("tunnel_incoming"))
        app_b = self.b.app_socket("peer=pc-a")              # B's app opens a session to A
        for _ in range(50):
            incoming = self.a.events("tunnel_incoming")
            if len(incoming) > before:
                break
            time.sleep(0.1)
        event = incoming[-1]
        self.assertEqual(event["peer"]["id"], "pc-b")
        app_a = self.a.app_socket("accept=" + event["tunnelId"])   # A's app picks it up

        # Opaque binary frames pass through unchanged, both ways, in order.
        big = os.urandom(1_000_000)
        app_b.send(b"\x05hello")
        app_b.send(big)
        self.assertEqual(app_a.recv(), (2, b"\x05hello"))
        self.assertEqual(app_a.recv(), (2, big))
        app_a.send(b"\x06accept")
        self.assertEqual(app_b.recv(), (2, b"\x06accept"))
        # A burst larger than the socket buffers: the relay applies backpressure, nothing is lost.
        received = []
        reader = threading.Thread(target=lambda: received.extend(app_a.recv()[1] for _ in range(200)))
        reader.start()
        for i in range(200):
            app_b.send(bytes([i % 256]) * 16411)
        reader.join(timeout=30)
        self.assertEqual(received, [bytes([i % 256]) * 16411 for i in range(200)])

        # Closing one end tears the whole tunnel down.
        app_b.close()
        with self.assertRaises(qs.WsClosed):
            app_a.recv()

        # The same picked-up tunnel cannot be claimed twice.
        self.assertEqual(status_of(lambda: self.a.get("/api/lan/tunnel?accept=" + event["tunnelId"])), 404)

    def test_5_unpaired_device_cannot_open_a_session(self):
        with self.assertRaises(PermissionError):
            qs.ws_connect("127.0.0.1", 18088, "/api/v2/session?from=evil")

    def test_6_v1_transfers_are_refused(self):
        req = urllib.request.Request("http://127.0.0.1:18088/api/transfer", data=b"evil", method="POST",
                                     headers={"x-sender-id": "pc-b", "x-pair-token": "forged", "x-file-name": "x.exe"})
        self.assertEqual(status_of(lambda: urllib.request.urlopen(req, timeout=5)), 426)

    def test_7_unclaimed_incoming_session_is_closed(self):
        self.b.post_json("/api/lan/pair", {"code": "123456"})
        app_b = self.b.app_socket("peer=pc-a")
        # Nobody on A picks it up: after the pickup timeout (3 s here) the tunnel closes.
        start = time.time()
        with self.assertRaises((qs.WsClosed, OSError)):
            app_b.recv()
        self.assertLess(time.time() - start, 10)

    def test_8_streaming_save(self):
        folder = tempfile.mkdtemp(prefix="qs_stream_")
        try:
            sid = self.a.post_json(f"/api/stream/open?name=..%2F..%2Fevil.txt&dir={urllib.request.quote(folder)}", {})["id"]
            for piece in (b"abc", b"def" * 1000):
                self.a._request(f"/api/stream/append?id={sid}", piece, {"Content-Type": "application/octet-stream"})
            done = self.a.post_json(f"/api/stream/commit?id={sid}", {})
            self.assertEqual(os.path.dirname(done["path"]), folder, "path traversal is stripped")
            self.assertEqual(os.path.basename(done["path"]), "evil.txt")
            with open(done["path"], "rb") as f:
                self.assertEqual(f.read(), b"abc" + b"def" * 1000)
            self.assertFalse([n for n in os.listdir(folder) if n.endswith(".part")])

            sid = self.a.post_json(f"/api/stream/open?name=x.bin&dir={urllib.request.quote(folder)}", {})["id"]
            self.a._request(f"/api/stream/append?id={sid}", b"partial", {"Content-Type": "application/octet-stream"})
            self.a.post_json(f"/api/stream/discard?id={sid}", {})
            self.assertEqual(sorted(os.listdir(folder)), ["evil.txt"], "discarded data is deleted")
        finally:
            shutil.rmtree(folder, ignore_errors=True)

    def test_9_app_api_is_not_exposed_to_other_sites_or_the_network(self):
        evil_origin = status_of(lambda: self.a.get("/api/lan/peers", headers={"Origin": "https://evil.example"}))
        self.assertEqual(evil_origin, 403)
        rebinding = status_of(lambda: self.a.get("/api/lan/peers", headers={"Host": "evil.example"}))
        self.assertEqual(rebinding, 403)
        # The LAN port only speaks the peer protocol: no tokens, tunnels or file saving there.
        for path in ("/api/lan/peers", "/api/lan/tunnel?peer=pc-b"):
            self.assertEqual(status_of(lambda: urllib.request.urlopen(f"http://127.0.0.1:18088{path}", timeout=5)), 404)
        lan_save = status_of(lambda: urllib.request.urlopen(urllib.request.Request(
            "http://127.0.0.1:18088/api/save-file?name=x.txt", data=b"x", method="POST"), timeout=5))
        self.assertEqual(lan_save, 404)

    def test_zz_wrong_codes_are_rate_limited(self):
        def try_code():
            req = urllib.request.Request("http://127.0.0.1:18088/api/pair", method="POST",
                                         data=json.dumps({"code": "999999", "id": "attacker"}).encode())
            return status_of(lambda: urllib.request.urlopen(req, timeout=5))
        codes = [try_code() for _ in range(10)]
        self.assertIn(429, codes)
        self.assertEqual(codes[0], 403)


if __name__ == "__main__":
    unittest.main(verbosity=2)
