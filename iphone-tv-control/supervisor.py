"""Mantém o servidor local ativo enquanto o Windows estiver ligado e a sessão aberta."""

import argparse
import json
import pathlib
import socket
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parent


def command(config):
    if set(config) != {"bind", "subnet", "tv", "port"}:
        raise ValueError("Configuração do serviço incompleta")
    return [sys.executable, str(ROOT / "server.py"),
            "--bind", config["bind"], "--subnet", config["subnet"],
            "--tv", config["tv"], "--port", str(config["port"]), "--background-pin"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=pathlib.Path, required=True)
    args = parser.parse_args()
    config = json.loads(args.config.read_text(encoding="utf-8-sig"))
    cmd = command(config)
    # A loopback-only lock prevents a second supervisor from repeatedly starting a server.
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as lock:
        if hasattr(socket, "SO_EXCLUSIVEADDRUSE"):
            lock.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
        lock.bind(("127.0.0.1", 18765))
        lock.listen(1)
        while True:
            try:
                process = subprocess.Popen(cmd, cwd=ROOT, stdin=subprocess.DEVNULL,
                                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                           creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
                process.wait()
            except OSError:
                pass
            time.sleep(10)


if __name__ == "__main__":
    main()
