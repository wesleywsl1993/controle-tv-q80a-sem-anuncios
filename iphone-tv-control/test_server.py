"""Bounded tests for LAN auth and command validation; never contacts the TV."""

import http.client
import ipaddress
import json
import pathlib
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


if __name__ == "__main__":
    unittest.main()
