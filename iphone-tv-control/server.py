"""Private LAN HTTPS remote; Samsung token stays in the PowerShell bridge."""

import argparse
import datetime as dt
import hmac
import ipaddress
import json
import pathlib
import secrets
import ssl
import subprocess
import threading
import time
from http import cookies
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID


ROOT = pathlib.Path(__file__).resolve().parent
LOCAL = ROOT / ".local"
PAGE = (ROOT / "index.html").read_bytes()
ALLOWED_KEYS = frozenset("KEY_UP KEY_DOWN KEY_LEFT KEY_RIGHT KEY_ENTER KEY_RETURN KEY_HOME KEY_MENU KEY_VOLUP KEY_VOLDOWN KEY_MUTE KEY_CHUP KEY_CHDOWN KEY_PLAY KEY_PAUSE KEY_STOP KEY_REWIND KEY_FF KEY_POWER".split())
DEFAULT_APPS = {"spotify": "201606009684", "youtube": "111299001912", "netflix": "3201907018807"}


def local_ipv4(value):
    address = ipaddress.ip_address(value)
    if not isinstance(address, ipaddress.IPv4Address) or not (
        address in ipaddress.ip_network("10.0.0.0/8")
        or address in ipaddress.ip_network("172.16.0.0/12")
        or address in ipaddress.ip_network("192.168.0.0/16")
    ) or str(address) != value:
        raise ValueError("Use um IPv4 privado literal")
    return address


def certificate(ip):
    LOCAL.mkdir(exist_ok=True)
    cert_path, key_path = LOCAL / "server.crt", LOCAL / "server.key"
    if cert_path.exists() != key_path.exists():
        raise RuntimeError("Certificado HTTPS incompleto; confira .local")
    if not cert_path.exists():
        private_key = rsa.generate_private_key(public_exponent=65537, key_size=3072)
        now = dt.datetime.now(dt.timezone.utc)
        subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "Controle Q80A local")])
        cert = (
            x509.CertificateBuilder()
            .subject_name(subject)
            .issuer_name(subject)
            .public_key(private_key.public_key())
            .serial_number(x509.random_serial_number())
            .not_valid_before(now - dt.timedelta(minutes=5))
            .not_valid_after(now + dt.timedelta(days=365))
            .add_extension(x509.SubjectAlternativeName([x509.IPAddress(ip)]), critical=False)
            .sign(private_key, hashes.SHA256())
        )
        key_path.write_bytes(private_key.private_bytes(
            serialization.Encoding.PEM, serialization.PrivateFormat.TraditionalOpenSSL,
            serialization.NoEncryption()))
        cert_path.write_bytes(cert.public_bytes(serialization.Encoding.PEM))
    cert = x509.load_pem_x509_certificate(cert_path.read_bytes())
    if not cert.not_valid_before_utc <= dt.datetime.now(dt.timezone.utc) <= cert.not_valid_after_utc:
        raise RuntimeError("Certificado HTTPS expirado; renove-o deliberadamente")
    names = cert.extensions.get_extension_for_class(x509.SubjectAlternativeName).value
    if ip not in names.get_values_for_type(x509.IPAddress):
        raise RuntimeError("IP do Windows mudou; o certificado local precisa ser renovado conscientemente")
    return cert_path, key_path, cert.fingerprint(hashes.SHA256()).hex().upper()


class Bridge:
    def __init__(self, tv_ip):
        self.lock = threading.Lock()
        self.process = subprocess.Popen(
            ["pwsh", "-NoProfile", "-File", str(ROOT / "bridge.ps1"), "-TvIp", tv_ip],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            text=True, encoding="utf-8", bufsize=1,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
        ready = self.process.stdout.readline()
        if not ready or json.loads(ready).get("message") != "ready":
            raise RuntimeError("Ponte com a TV não iniciou. Confira token e certificado fixado.")

    def request(self, value):
        with self.lock:
            try:
                self.process.stdin.write(json.dumps(value, ensure_ascii=False) + "\n")
                self.process.stdin.flush()
                answer = self.process.stdout.readline()
                if not answer:
                    raise RuntimeError("Ponte encerrada")
                return json.loads(answer)
            except (OSError, ValueError, RuntimeError):
                return {"ok": False, "message": "Conexão com a TV indisponível"}

    def close(self):
        self.process.terminate()
        try:
            self.process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            self.process.kill()


class ControlServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address, handler, tv_ip, subnet, http_test=False):
        super().__init__(address, handler)
        self.host_header = f"{address[0]}:{address[1]}"
        self.origin = f"{'http' if http_test else 'https'}://{self.host_header}"
        self.http_test = http_test
        self.paired_ip = None
        self.session_expires = None
        self.subnet = subnet
        self.bridge = Bridge(tv_ip)
        self.pin = f"{secrets.randbelow(100_000_000):08d}"
        self.pin_expires = time.monotonic() + 600
        self.attempts = {}
        self.csrf = secrets.token_urlsafe(24)
        self.session_file = LOCAL / "session.bin"
        self.session = self.session_file.read_bytes() if self.session_file.exists() and not http_test else None
        self.app_file = LOCAL / "apps.json"
        self.apps = dict(DEFAULT_APPS)
        if self.app_file.exists():
            stored = json.loads(self.app_file.read_text(encoding="utf-8"))
            for name in self.apps:
                value = stored.get(name, self.apps[name])
                if valid_app_id(value):
                    self.apps[name] = value


def valid_app_id(value):
    return isinstance(value, str) and 1 <= len(value) <= 80 and all(
        char.isascii() and (char.isalnum() or char in "._-") for char in value)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass  # Never log PIN, cookies, paths, input text, or commands.

    def respond(self, code, body, content_type="application/json; charset=utf-8", cookie=None):
        if not isinstance(body, bytes):
            body = json.dumps(body, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Permissions-Policy", "camera=(), microphone=(), geolocation=()")
        self.send_header("Content-Security-Policy", "default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self' data:; form-action 'self'; frame-ancestors 'none'; base-uri 'none'")
        if cookie:
            self.send_header("Set-Cookie", cookie)
        self.end_headers()
        self.wfile.write(body)

    def guard(self):
        try:
            caller = ipaddress.ip_address(self.client_address[0])
            valid = caller in self.server.subnet
        except ValueError:
            valid = False
        if not valid or self.headers.get("Host") != self.server.host_header:
            self.respond(403, {"error": "Acesso negado"})
            return False
        return True

    def authenticated(self):
        if not self.server.session:
            return False
        if self.server.http_test and (
            self.client_address[0] != self.server.paired_ip
            or self.server.session_expires is None
            or time.monotonic() >= self.server.session_expires
        ):
            return False
        try:
            cookie = cookies.SimpleCookie(self.headers.get("Cookie", ""))
            candidate = bytes.fromhex(cookie["q80a_session"].value)
        except (ValueError, KeyError, cookies.CookieError):
            return False
        return hmac.compare_digest(candidate, self.server.session)

    def do_GET(self):
        if not self.guard():
            return
        if self.path == "/":
            return self.respond(200, PAGE, "text/html; charset=utf-8")
        if self.path == "/app.css":
            return self.respond(200, (ROOT / "app.css").read_bytes(), "text/css; charset=utf-8")
        if self.path == "/app.js":
            return self.respond(200, (ROOT / "app.js").read_bytes(), "text/javascript; charset=utf-8")
        if self.path == "/api/status":
            if not self.authenticated():
                return self.respond(401, {"paired": False})
            result = self.server.bridge.request({"type": "status"})
            return self.respond(200, {"paired": True, "connected": bool(result.get("ok")),
                "message": result.get("message"), "csrf": self.server.csrf,
                "apps": self.server.apps})
        self.respond(404, {"error": "Não encontrado"})

    def do_POST(self):
        if not self.guard():
            return
        if self.headers.get("Origin") != self.server.origin or self.headers.get("Content-Type", "").split(";")[0] != "application/json":
            return self.respond(403, {"error": "Origem inválida"})
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if not 1 <= length <= 4096:
                return self.respond(413, {"error": "Pedido muito grande"})
            data = json.loads(self.rfile.read(length))
            if not isinstance(data, dict):
                raise ValueError()
        except (ValueError, UnicodeError):
            return self.respond(400, {"error": "Pedido inválido"})
        if self.path == "/api/pair":
            caller = self.client_address[0]
            attempts = self.server.attempts.get(caller, 0)
            if attempts >= 5 or time.monotonic() > self.server.pin_expires or not self.server.pin:
                return self.respond(429, {"error": "Pareamento expirou; reinicie o servidor no Windows"})
            if not isinstance(data.get("pin"), str) or not hmac.compare_digest(data["pin"], self.server.pin):
                self.server.attempts[caller] = attempts + 1
                return self.respond(403, {"error": "Código incorreto"})
            self.server.pin = None
            self.server.session = secrets.token_bytes(32)
            if not self.server.http_test:
                self.server.session_file.write_bytes(self.server.session)
            else:
                self.server.paired_ip = caller
                self.server.session_expires = time.monotonic() + 3600
            secure = "" if self.server.http_test else " Secure;"
            return self.respond(200, {"paired": True}, cookie=
                f"q80a_session={self.server.session.hex()}; HttpOnly;{secure} SameSite=Strict; Path=/; Max-Age={3600 if self.server.http_test else 2592000}")
        if not self.authenticated() or not hmac.compare_digest(self.headers.get("X-CSRF-Token", ""), self.server.csrf):
            return self.respond(403, {"error": "Sessão inválida"})
        if self.path == "/api/command":
            kind = data.get("type")
            if kind == "key" and data.get("key") in ALLOWED_KEYS and type(data.get("count")) is int and 1 <= data["count"] <= 8:
                request = {"type": "key", "key": data["key"], "count": data["count"]}
            elif kind == "text" and isinstance(data.get("value"), str) and 1 <= len(data["value"]) <= 200:
                request = {"type": "text", "value": data["value"]}
            elif kind == "app" and data.get("app") in self.server.apps:
                request = {"type": "app", "id": self.server.apps[data["app"]]}
            else:
                return self.respond(400, {"error": "Comando inválido"})
            answer = self.server.bridge.request(request)
            return self.respond(200 if answer.get("ok") else 503, answer)
        if self.path == "/api/apps":
            if set(data) != set(DEFAULT_APPS) or not all(valid_app_id(value) for value in data.values()):
                return self.respond(400, {"error": "IDs inválidos"})
            self.server.apps = dict(data)
            self.server.app_file.write_text(json.dumps(data), encoding="utf-8")
            return self.respond(200, {"ok": True})
        self.respond(404, {"error": "Não encontrado"})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bind", required=True, help="IPv4 privado deste Windows na rede da TV")
    parser.add_argument("--subnet", required=True, help="Sub-rede privada permitida em formato CIDR")
    parser.add_argument("--tv", required=True, help="IPv4 privado da TV")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--http-test", action="store_true", help="Temporary private-LAN test without TLS; session stays in memory")
    args = parser.parse_args()
    ip, tv_ip = local_ipv4(args.bind), local_ipv4(args.tv)
    subnet = ipaddress.ip_network(args.subnet, strict=True)
    if ip not in subnet or not 1024 <= args.port <= 65535:
        parser.error("IP, sub-rede ou porta inválidos")
    server = ControlServer((str(ip), args.port), Handler, str(tv_ip), subnet, args.http_test)
    if not args.http_test:
        cert_path, key_path, fingerprint = certificate(ip)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        context.load_cert_chain(str(cert_path), str(key_path))
        server.socket = context.wrap_socket(server.socket, server_side=True)
        print(f"Controle local: https://{ip}:{args.port}/", flush=True)
        print(f"Impressão SHA-256 do certificado HTTPS: {fingerprint}", flush=True)
    else:
        print(f"TESTE HTTP SEM CRIPTOGRAFIA: http://{ip}:{args.port}/", flush=True)
    print(f"PIN de pareamento do iPhone (10 min, uma vez): {server.pin}", flush=True)
    print("Mantenha este Windows ligado; Ctrl+C encerra.", flush=True)
    try:
        server.serve_forever()
    finally:
        server.bridge.close()
        server.server_close()


if __name__ == "__main__":
    main()
