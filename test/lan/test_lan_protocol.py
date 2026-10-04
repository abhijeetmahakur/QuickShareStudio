"""End-to-end test of the LAN peer protocol in scripts/server.py.

Starts two independent server instances ("PC A" and "PC B") on one machine and checks
discovery, code pairing, transfers in both directions, and the security rules.

    python test/lan/test_lan_protocol.py
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SERVER = os.path.join(ROOT, "scripts", "server.py")


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

    def test_2_wrong_code_is_rejected(self):
        code = status_of(lambda: self.b.post_json("/api/lan/pair", {"code": "000000"}))
        self.assertEqual(code, 404)

    def test_3_own_code_is_rejected(self):
        code = status_of(lambda: self.b.post_json("/api/lan/pair", {"code": "654321"}))
        self.assertEqual(code, 400)

    def test_4_pair_by_code_and_transfer_both_ways(self):
        paired = self.b.post_json("/api/lan/pair", {"code": "123456"})["device"]
        self.assertEqual(paired["id"], "pc-a")
        self.assertEqual(paired["name"], "PC A")

        # A learned about B through the pairing request.
        events_a = self.a.get("/api/lan/events?since=0")["events"]
        self.assertTrue(any(e["type"] == "peer_paired" and e["device"]["id"] == "pc-b" for e in events_a))

        payload = os.urandom(300_000) + "नमस्ते".encode()
        sent = self.b.get("/api/lan/send?peer=pc-a&name=Lab%20Report.pdf", data=payload)
        self.assertEqual(sent["status"], "sent")

        received = [e for e in self.a.get("/api/lan/events?since=0")["events"] if e["type"] == "file_received"]
        self.assertEqual(received[-1]["fileName"], "Lab Report.pdf")
        self.assertEqual(received[-1]["sender"]["id"], "pc-b")
        self.assertEqual(self.a.get(f"/api/lan/file?id={received[-1]['fileId']}"), payload)
        self.assertTrue(os.path.isfile(received[-1]["path"]))

        # And back from A to B with the token from the same pairing.
        back = self.a.get("/api/lan/send?peer=pc-b&name=reply.txt", data=b"got it")
        self.assertEqual(back["status"], "sent")
        received_b = [e for e in self.b.get("/api/lan/events?since=0")["events"] if e["type"] == "file_received"]
        self.assertEqual(self.b.get(f"/api/lan/file?id={received_b[-1]['fileId']}"), b"got it")

    def test_5_unpaired_sender_is_refused(self):
        req = urllib.request.Request("http://127.0.0.1:18088/api/transfer", data=b"evil", method="POST",
                                     headers={"x-sender-id": "pc-b", "x-pair-token": "forged", "x-file-name": "x.exe"})
        self.assertEqual(status_of(lambda: urllib.request.urlopen(req, timeout=5)), 401)

    def test_6_app_api_is_not_exposed_to_other_sites_or_the_network(self):
        evil_origin = status_of(lambda: self.a.get("/api/lan/events", headers={"Origin": "https://evil.example"}))
        self.assertEqual(evil_origin, 403)
        rebinding = status_of(lambda: self.a.get("/api/lan/events", headers={"Host": "evil.example"}))
        self.assertEqual(rebinding, 403)
        # The LAN port only speaks the peer protocol.
        lan_save = status_of(lambda: urllib.request.urlopen(urllib.request.Request(
            "http://127.0.0.1:18088/api/save-file?name=x.txt", data=b"x", method="POST"), timeout=5))
        self.assertEqual(lan_save, 404)

    def test_7_wrong_codes_are_rate_limited(self):
        def try_code():
            req = urllib.request.Request("http://127.0.0.1:18088/api/pair", method="POST",
                                         data=json.dumps({"code": "999999", "id": "attacker"}).encode())
            return status_of(lambda: urllib.request.urlopen(req, timeout=5))
        codes = [try_code() for _ in range(10)]
        self.assertIn(429, codes)
        self.assertEqual(codes[0], 403)


if __name__ == "__main__":
    unittest.main(verbosity=2)
