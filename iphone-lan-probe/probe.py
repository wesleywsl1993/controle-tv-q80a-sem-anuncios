"""Read-only LAN/Safari diagnostic. No TV access, tokens, or state-changing routes."""

import argparse
import ipaddress
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


PAGE = """<!doctype html>
<html lang="pt-BR">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
  <meta name="apple-mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-title" content="Teste Q80A">
  <meta name="theme-color" content="#080b12">
  <title>Teste local Q80A</title>
  <style>
    :root { color-scheme: dark; font: 16px -apple-system, BlinkMacSystemFont, sans-serif; }
    body { margin: 0; background: #080b12; color: #f4f7ff; }
    main { max-width: 480px; margin: auto; padding: max(22px, env(safe-area-inset-top)) 20px 32px; }
    h1 { font-size: 1.55rem; margin: 10px 0; }
    p { color: #b8c3d5; line-height: 1.45; }
    .card { background: #151b28; border-radius: 18px; padding: 18px; margin: 18px 0; }
    dl { display: grid; grid-template-columns: 1fr auto; gap: 12px; margin: 0; }
    dt { color: #b8c3d5; } dd { margin: 0; font-weight: 650; }
    button, input { font: inherit; border-radius: 12px; min-height: 50px; box-sizing: border-box; }
    button { width: 100%; background: #78a9ff; color: #080b12; font-weight: 700; border: 0; }
    input { width: 100%; padding: 12px; color: #fff; background: #080b12; border: 1px solid #77849a; }
    .small { font-size: .86rem; }
    #reply { min-height: 1.5em; }
  </style>
</head>
<body>
<main>
  <h1>Teste local Q80A</h1>
  <p>Esta página testa apenas o acesso do iPhone ao Windows. Não conhece a TV, não pede senha e não envia comandos.</p>
  <section class="card">
    <dl>
      <dt>Origem</dt><dd id="origin">—</dd>
      <dt>Contexto seguro</dt><dd id="secure">—</dd>
      <dt>API de service worker visível</dt><dd id="worker">—</dd>
      <dt>Tela inicial</dt><dd id="standalone">—</dd>
    </dl>
  </section>
  <section class="card">
    <button id="check" type="button">Testar comunicação com Windows</button>
    <p id="reply" role="status" aria-live="polite">Toque para testar.</p>
  </section>
  <section class="card">
    <label for="keyboard">Testar teclado do iPhone</label>
    <p class="small">Digite algo sem dados pessoais. O texto fica somente nesta página.</p>
    <input id="keyboard" type="text" autocomplete="off" autocorrect="off" spellcheck="false" placeholder="Ex.: ação 123">
    <p id="typed" role="status" aria-live="polite">Nenhum texto digitado.</p>
  </section>
  <p class="small">Depois, no Safari, use Compartilhar → Adicionar à Tela de Início e abra o ícone. Compare os indicadores acima. Esta página não registra service worker; HTTP local não garante recursos de PWA offline.</p>
</main>
<script>
  const byId = id => document.getElementById(id);
  byId('origin').textContent = location.protocol + '//' + location.host;
  byId('secure').textContent = window.isSecureContext ? 'sim' : 'não';
  byId('worker').textContent = 'serviceWorker' in navigator ? 'sim' : 'não';
  byId('standalone').textContent =
    (navigator.standalone === true || matchMedia('(display-mode: standalone)').matches) ? 'sim' : 'não';
  byId('keyboard').addEventListener('input', event => {
    byId('typed').textContent = event.target.value || 'Nenhum texto digitado.';
  });
  byId('check').addEventListener('click', async () => {
    byId('reply').textContent = 'Testando…';
    try {
      const response = await fetch('/health', {cache: 'no-store', credentials: 'omit'});
      const result = await response.json();
      byId('reply').textContent = response.ok && result.status === 'ok'
        ? 'Windows respondeu. Conexão local OK.' : 'Resposta inesperada.';
    } catch (_) {
      byId('reply').textContent = 'Sem resposta. Confira Wi-Fi e firewall.';
    }
  });
</script>
</body>
</html>
""".encode("utf-8")


def make_handler(bind_ip: str, allowed_subnet: ipaddress.IPv4Network, port: int):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, _format, *_args):
            # Do not log paths, query strings, headers, or keyboard input.
            pass

        def _reply(self, status: int, content_type: str, body: bytes):
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("X-Frame-Options", "DENY")
            self.send_header("Referrer-Policy", "no-referrer")
            self.send_header(
                "Content-Security-Policy",
                "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; "
                "connect-src 'self'; form-action 'none'; frame-ancestors 'none'",
            )
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            try:
                caller = ipaddress.ip_address(self.client_address[0])
            except ValueError:
                caller = None
            if (
                not isinstance(caller, ipaddress.IPv4Address)
                or caller not in allowed_subnet
                or self.headers.get("Host") != f"{bind_ip}:{port}"
            ):
                self._reply(403, "text/plain; charset=utf-8", b"Forbidden")
                return
            if self.path == "/":
                self._reply(200, "text/html; charset=utf-8", PAGE)
            elif self.path == "/health":
                self._reply(200, "application/json; charset=utf-8", b'{"status":"ok"}')
            else:
                self._reply(404, "text/plain; charset=utf-8", b"Not found")

        def do_POST(self):
            self._reply(405, "text/plain; charset=utf-8", b"Method not allowed")

    return Handler


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bind", required=True, help="IPv4 privado da interface Wi-Fi do Windows")
    parser.add_argument("--subnet", required=True, help="Sub-rede privada permitida em formato CIDR")
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    bind_ip = ipaddress.ip_address(args.bind)
    subnet = ipaddress.ip_network(args.subnet, strict=True)
    if (
        not isinstance(bind_ip, ipaddress.IPv4Address)
        or not bind_ip.is_private
        or not isinstance(subnet, ipaddress.IPv4Network)
        or bind_ip not in subnet
        or not 1024 <= args.port <= 65535
    ):
        parser.error("Use um IPv4 privado da LAN, uma sub-rede que o inclua e porta 1024..65535")
    with ThreadingHTTPServer(
        (str(bind_ip), args.port), make_handler(str(bind_ip), subnet, args.port)
    ) as server:
        server.daemon_threads = True
        print(f"Diagnostico ativo: http://{bind_ip}:{args.port}/", flush=True)
        print("Somente diagnostico; Ctrl+C encerra.", flush=True)
        server.serve_forever()


if __name__ == "__main__":
    main()
