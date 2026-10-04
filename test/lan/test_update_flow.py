"""In-app update of the packaged desktop app (scripts/server.py), end to end:

an "old" packaged install detects a newer release, downloads it from a local stand-in for
GitHub, verifies its SHA-256, swaps the bundle and restarts on the same port.

    python test/lan/test_update_flow.py
"""
import hashlib
import http.server
import json
import os
import shutil
import socketserver
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import urllib.error
import urllib.request
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SERVER = os.path.join(ROOT, "scripts", "server.py")


def make_package(folder, version, marker):
    """A release zip shaped like QuickShareStudio-Windows-x64.zip."""
    pkg = os.path.join(folder, "QuickShareStudio-Windows")
    os.makedirs(os.path.join(pkg, "web"))
    with open(os.path.join(pkg, "web", "index.html"), "w") as f:
        f.write(f"<html>{marker}</html>")
    shutil.copy(SERVER, pkg)
    with open(os.path.join(pkg, "VERSION"), "w") as f:
        f.write(version)
    archive = os.path.join(folder, "QuickShareStudio-Windows-x64.zip")
    with zipfile.ZipFile(archive, "w") as z:
        for base, _, files in os.walk(pkg):
            for name in files:
                full = os.path.join(base, name)
                z.write(full, os.path.relpath(full, folder))
    with open(archive, "rb") as f:
        return archive, hashlib.sha256(f.read()).hexdigest()


def wait_for_port_file(folder):
    port_file = os.path.join(folder, "active_port.txt")
    for _ in range(100):
        if os.path.exists(port_file):
            with open(port_file) as f:
                text = f.read().strip()
            if text:
                return int(text)
        time.sleep(0.1)
    raise RuntimeError("server did not start")


class Installed:
    """A packaged install: server.py + web/ + VERSION in one folder."""

    def __init__(self, version, allow_any_url=True):
        self.dir = tempfile.mkdtemp(prefix="qs_installed_")
        shutil.copy(SERVER, self.dir)
        os.makedirs(os.path.join(self.dir, "web"))
        with open(os.path.join(self.dir, "web", "index.html"), "w") as f:
            f.write("<html>old</html>")
        with open(os.path.join(self.dir, "VERSION"), "w") as f:
            f.write(version)
        env = dict(os.environ, QUICKSHARE_NO_LAN="1")
        if allow_any_url:
            env["QUICKSHARE_UPDATE_ALLOW_ANY_URL"] = "1"
        self.proc = subprocess.Popen([sys.executable, os.path.join(self.dir, "server.py")], cwd=self.dir, env=env)
        self.port = wait_for_port_file(self.dir)

    def api(self, path, payload=None):
        data = None if payload is None else json.dumps(payload).encode()
        req = urllib.request.Request(f"http://127.0.0.1:{self.port}{path}", data=data,
                                     method="POST" if data else "GET",
                                     headers={"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=10) as r:
                return r.status, json.loads(r.read())
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read())

    def page(self):
        with urllib.request.urlopen(f"http://127.0.0.1:{self.port}/index.html", timeout=10) as r:
            return r.read().decode()

    def stop(self):
        try:
            pid = self.api("/api/update/status")[1]["pid"]
            os.kill(pid, 9)
        except Exception:
            pass
        self.proc.kill()
        time.sleep(0.5)
        shutil.rmtree(self.dir, ignore_errors=True)


class UpdateFlowTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.release_dir = tempfile.mkdtemp(prefix="qs_release_")
        cls.archive, cls.sha = make_package(cls.release_dir, "9.9.9", "new-version-marker")
        directory = cls.release_dir

        class Quiet(http.server.SimpleHTTPRequestHandler):
            def __init__(self, *a, **k):
                super().__init__(*a, directory=directory, **k)

            def log_message(self, *args):
                pass

        cls.http = socketserver.TCPServer(("127.0.0.1", 0), Quiet)
        threading.Thread(target=cls.http.serve_forever, daemon=True).start()
        cls.url = f"http://127.0.0.1:{cls.http.server_address[1]}/QuickShareStudio-Windows-x64.zip"

    @classmethod
    def tearDownClass(cls):
        cls.http.shutdown()
        shutil.rmtree(cls.release_dir, ignore_errors=True)

    def test_1_bad_checksum_changes_nothing(self):
        app = Installed("2.0.0")
        try:
            code, _ = app.api("/api/update/apply", {"url": self.url, "sha256": "0" * 64, "version": "9.9.9"})
            self.assertEqual(code, 200)
            status = {}
            for _ in range(50):
                status = app.api("/api/update/status")[1]
                if status["state"] in ("failed", "restarting"):
                    break
                time.sleep(0.1)
            self.assertEqual(status["state"], "failed")
            self.assertIn("checksum", status["error"])
            self.assertEqual(status["version"], "2.0.0")
            self.assertIn("old", app.page())
        finally:
            app.stop()

    def test_2_old_version_updates_and_restarts_on_the_same_port(self):
        app = Installed("2.0.0")
        try:
            status = app.api("/api/update/status")[1]
            self.assertEqual(status["version"], "2.0.0")
            self.assertTrue(status["packaged"])
            old_pid = status["pid"]
            code, body = app.api("/api/update/apply", {"url": self.url, "sha256": self.sha, "version": "9.9.9"})
            self.assertEqual(code, 200, body)
            new = None
            for _ in range(100):
                time.sleep(0.2)
                try:
                    status = app.api("/api/update/status")[1]
                except Exception:
                    continue  # restarting
                if status["pid"] != old_pid:
                    new = status
                    break
            self.assertIsNotNone(new, "the launcher did not restart")
            self.assertEqual(new["version"], "9.9.9")
            self.assertIn("new-version-marker", app.page())
            self.assertFalse(os.path.exists(os.path.join(app.dir, "web.old")))
        finally:
            app.stop()

    def test_3_only_github_release_urls_are_accepted(self):
        app = Installed("2.0.0", allow_any_url=False)
        try:
            code, body = app.api("/api/update/apply", {"url": "https://evil.example/x.zip", "sha256": "a" * 64})
            self.assertEqual(code, 400)
            self.assertIn("GitHub", body["error"])
            code, body = app.api("/api/update/apply", {"url": self.url, "sha256": self.sha})
            self.assertEqual(code, 400, "a non-GitHub URL is refused outside tests")
        finally:
            app.stop()

    def test_4_source_checkouts_are_not_self_updated(self):
        # A source checkout: <repo>/lib, <repo>/scripts/server.py serving <repo>/build/web.
        repo = tempfile.mkdtemp(prefix="qs_checkout_")
        os.makedirs(os.path.join(repo, "lib"))
        os.makedirs(os.path.join(repo, "scripts"))
        build_web = os.path.join(repo, "build", "web")
        os.makedirs(build_web)
        shutil.copy(SERVER, os.path.join(repo, "scripts"))
        env = dict(os.environ, QUICKSHARE_NO_LAN="1", QUICKSHARE_UPDATE_ALLOW_ANY_URL="1")
        proc = subprocess.Popen([sys.executable, os.path.join(repo, "scripts", "server.py")], cwd=repo, env=env)
        try:
            port = wait_for_port_file(os.path.join(repo, "scripts"))
            req = urllib.request.Request(f"http://127.0.0.1:{port}/api/update/apply", method="POST",
                                         data=json.dumps({"url": self.url, "sha256": self.sha}).encode())
            with self.assertRaises(urllib.error.HTTPError) as err:
                urllib.request.urlopen(req, timeout=10)
            self.assertEqual(err.exception.code, 501)
        finally:
            proc.kill()
            time.sleep(0.3)
            shutil.rmtree(repo, ignore_errors=True)


if __name__ == "__main__":
    unittest.main(verbosity=2)
