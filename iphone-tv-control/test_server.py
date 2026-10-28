"""Bounded tests for LAN auth and command validation; never contacts the TV."""

import http.client
import ipaddress
import json
import pathlib
import subprocess
import sys
import time
import tempfile
import threading
import unittest
from unittest.mock import patch

import server


class FakeBridge:
    def __init__(self, _tv_ip):
        self.calls = []

    def request(self, value):
        self.calls.append(value)
        return {"ok": True, "message": "TV conectada"}

    def status(self):
        return {"ok": True, "message": "TV conectada"}

    def close(self):
        pass


class ControlServerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.original_local = server.LOCAL
        server.LOCAL = pathlib.Path(self.temp.name)
        self.mock_bridge = patch.object(server, "Bridge", FakeBridge)
        self.mock_bridge.start()
        self.http = server.ControlServer(
            ("127.0.0.1", 0), server.Handler, "192.168.12.20",
            ipaddress.ip_network("127.0.0.0/8"),
        )
        self.http.host_header = f"127.0.0.1:{self.http.server_port}"
        self.http.origin = "https://" + self.http.host_header
        self.thread = threading.Thread(target=self.http.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.http.shutdown()
        self.http.server_close()
        self.thread.join(timeout=2)
        self.mock_bridge.stop()
        server.LOCAL = self.original_local
        self.temp.cleanup()

    def call(self, method, path, body=None, headers=None):
        connection = http.client.HTTPConnection("127.0.0.1", self.http.server_port, timeout=3)
        request_headers = {"Host": self.http.host_header, **(headers or {})}
        if body is not None:
            request_headers["Content-Type"] = "application/json"
            body = json.dumps(body)
        connection.request(method, path, body=body, headers=request_headers)
        response = connection.getresponse()
        result = response.read()
        code, cookie = response.status, response.getheader("Set-Cookie")
        connection.close()
        return code, json.loads(result) if path.startswith("/api/") else result, cookie

    def test_pairing_and_allowlist(self):
        self.assertEqual(self.call("GET", "/api/status")[0], 401)
        self.assertEqual(self.call("POST", "/api/pair", {"pin": self.http.pin},
            {"Origin": "https://evil.example"})[0], 403)
        code, _, cookie = self.call("POST", "/api/pair", {"pin": self.http.pin},
            {"Origin": self.http.origin})
        self.assertEqual(code, 200)
        self.assertIn("HttpOnly", cookie)
        auth = {"Origin": self.http.origin, "Cookie": cookie.split(";", 1)[0],
                "X-CSRF-Token": self.http.csrf}
        self.assertEqual(self.call("POST", "/api/command",
            {"type": "key", "key": "KEY_FACTORY", "count": 1}, auth)[0], 400)
        self.assertEqual(self.call("POST", "/api/command",
            {"type": "key", "key": "KEY_HOME", "count": 1}, auth)[0], 200)
        self.assertEqual(self.http.bridge.calls, [{"type": "key", "key": "KEY_HOME", "count": 1}])

    def test_ip_and_app_id_validation(self):
        self.assertEqual(str(server.local_ipv4("192.168.12.10")), "192.168.12.10")
        for value in ("8.8.8.8", "192.168.0.040", "localhost"):
            with self.assertRaises(ValueError):
                server.local_ipv4(value)
        self.assertTrue(server.valid_app_id("3201907018807"))
        self.assertFalse(server.valid_app_id("http://example.com"))

    def test_http_test_session_is_ephemeral_and_ip_bound(self):
        self.http.http_test = True
        self.http.origin = "http://" + self.http.host_header
        code, _, cookie = self.call("POST", "/api/pair", {"pin": self.http.pin},
            {"Origin": self.http.origin})
        self.assertEqual(code, 200)
        self.assertNotIn("Secure;", cookie)
        self.assertFalse(self.http.session_file.exists())
        self.assertEqual(self.http.paired_ip, "127.0.0.1")
        self.assertEqual(self.call("GET", "/api/status",
            headers={"Cookie": cookie.split(";", 1)[0]})[0], 200)

    def test_https_session_survives_restart_and_renews_cookie(self):
        _, _, cookie = self.call("POST", "/api/pair", {"pin": self.http.pin},
                                 {"Origin": self.http.origin})
        _, _, renewed = self.call("GET", "/api/status",
                                  headers={"Cookie": cookie.split(";", 1)[0]})
        self.assertIn("Secure", renewed)
        second = server.ControlServer(("127.0.0.1", 0), server.Handler, "192.168.12.20",
                                      ipaddress.ip_network("127.0.0.0/8"))
        try:
            self.assertEqual(second.session, self.http.session)
            self.assertEqual(len(second.session), 32)
        finally:
            second.server_close()

    def test_background_pin_can_be_renewed_locally(self):
        saved = []
        with patch.object(server, "protect_pairing_pin", side_effect=lambda pin: saved.append(pin)):
            self.http.start_pin_worker()
            try:
                self.assertEqual(len(saved), 1)
                (server.LOCAL / "renew-pin.request").touch()
                deadline = time.monotonic() + 4
                while len(saved) < 2 and time.monotonic() < deadline:
                    time.sleep(0.05)
                self.assertEqual(len(saved), 2)
                self.assertEqual(self.http.pin, saved[-1])
            finally:
                self.http.pin_worker_stop.set()

    def test_wake_requires_authenticated_session_and_config(self):
        self.assertEqual(self.call("POST", "/api/wake", {}, {"Origin": self.http.origin})[0], 403)
        _, _, cookie = self.call("POST", "/api/pair", {"pin": self.http.pin},
                                 {"Origin": self.http.origin})
        auth = {"Origin": self.http.origin, "Cookie": cookie.split(";", 1)[0],
                "X-CSRF-Token": self.http.csrf}
        self.assertEqual(self.call("POST", "/api/wake", {}, auth)[0], 400)
        self.http.wake = {"mac": "02:11:22:33:44:55", "broadcast": "192.168.12.255"}
        with patch.object(server, "send_wake") as send:
            self.assertEqual(self.call("POST", "/api/wake", {}, auth)[0], 200)
            send.assert_called_once()

    def test_wake_packet_and_broadcast_validation(self):
        packet = server.wake_packet("02:11:22:33:44:55")
        self.assertEqual(len(packet), 102)
        self.assertEqual(packet[:6], b"\xff" * 6)
        self.assertEqual(packet[6:], bytes.fromhex("021122334455") * 16)
        subnet = ipaddress.ip_network("192.168.12.0/24")
        self.assertEqual(server.validate_wake("02:11:22:33:44:55", "192.168.12.255", subnet)["broadcast"], "192.168.12.255")
        for mac, broadcast in (("01:11:22:33:44:55", "192.168.12.255"),
                               ("02:11:22:33:44:55", "192.168.13.255")):
            with self.assertRaises(ValueError):
                server.validate_wake(mac, broadcast, subnet)

    def test_bridge_restarts_after_process_exit(self):
        self.mock_bridge.stop()
        real_popen = subprocess.Popen
        scripts = iter([
            "import sys; print('{\"message\":\"ready\"}', flush=True); sys.stdin.readline()",
            "import sys; print('{\"message\":\"ready\"}', flush=True); sys.stdin.readline(); print('{\"ok\":true}', flush=True)",
        ])
        def start_process(*_args, **kwargs):
            kwargs.pop("creationflags", None)
            return real_popen([sys.executable, "-u", "-c", next(scripts)], **kwargs)
        with patch.object(server.subprocess, "Popen", side_effect=start_process):
            bridge = server.Bridge("192.168.12.20")
            try:
                self.assertFalse(bridge.request({"type": "status"})["ok"])
                self.assertTrue(bridge.request({"type": "status"})["ok"])
            finally:
                bridge.close()

    def test_status_does_not_wait_for_unresponsive_tv(self):
        self.mock_bridge.stop()
        bridge = server.Bridge("192.168.12.20")
        started, release = threading.Event(), threading.Event()
        def slow_request(_request):
            started.set()
            release.wait(2)
            return {"ok": False, "message": "TV indisponível"}
        with patch.object(bridge, "request", side_effect=slow_request):
            result = bridge.status()
            self.assertFalse(result["ok"])
            self.assertTrue(started.wait(1))
            release.set()


if __name__ == "__main__":
    unittest.main()
