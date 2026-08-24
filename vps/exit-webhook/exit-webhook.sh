#!/usr/bin/env python3
"""exit-webhook — Fase 2.5.
Recebe POST do botão do ntfy e troca o exit via switch-exit.sh.
Roda como usuário SEM privilégio; escala só o switch-exit.sh por sudoers restrito.
Liga SÓ em 10.66.66.1 (guard rail: alcançável apenas pela WireGuard)."""
import os, sys, subprocess, urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST       = os.environ.get("WEBHOOK_HOST", "10.66.66.1")
PORT       = int(os.environ.get("WEBHOOK_PORT", "8088"))
TOKEN      = os.environ.get("WEBHOOK_TOKEN", "")
NTFY_URL   = os.environ.get("NTFY_URL", "https://ntfy.shost.me")
NTFY_TOPIC = os.environ.get("NTFY_TOPIC", "healthcheck")
NTFY_TOKEN = os.environ.get("NTFY_TOKEN", "")
SWITCH     = "/opt/homelab-monitor/vps/switch-exit/switch-exit.sh"

ACTIONS = {"/datacenter": "datacenter", "/residencial": "residencial", "/killswitch": "killswitch"}

def log(m): sys.stderr.write(f"[exit-webhook] {m}\n"); sys.stderr.flush()

def notify(title, message, tags="information_source", prio="default"):
    if not NTFY_TOKEN: return
    try:
        req = urllib.request.Request(
            f"{NTFY_URL}/{NTFY_TOPIC}", data=message.encode(),
            headers={"Authorization": f"Bearer {NTFY_TOKEN}", "Title": title,
                     "Tags": tags, "Priority": prio})
        urllib.request.urlopen(req, timeout=10)
    except Exception as e:
        log(f"falha ao notificar: {e}")

class H(BaseHTTPRequestHandler):
    def _send(self, code, body=b""):
        self.send_response(code); self.send_header("Content-Type", "text/plain"); self.end_headers()
        if body: self.wfile.write(body)
    def do_GET(self):
        self._send(200, b"ok\n") if self.path == "/healthz" else self._send(404, b"use POST\n")
    def do_POST(self):
        if not TOKEN or self.headers.get("Authorization", "") != f"Bearer {TOKEN}":
            log(f"auth negada de {self.client_address[0]} path={self.path}")
            return self._send(401, b"unauthorized\n")
        action = ACTIONS.get(self.path)
        if not action:
            return self._send(404, b"rota desconhecida\n")
        log(f"acao solicitada: {action} de {self.client_address[0]}")
        try:
            r = subprocess.run(["sudo", "-n", SWITCH, action],
                               capture_output=True, text=True, timeout=60)
        except Exception as e:
            log(f"erro exec: {e}"); notify("❌ Falha na troca", f"{action}: {e}", "x", "high")
            return self._send(500, f"erro: {e}\n".encode())
        ok = r.returncode == 0
        log(f"acao={action} rc={r.returncode}")
        if ok:
            notify(f"✅ Exit trocado -> {action}", "Troca aplicada pelo botão.", "white_check_mark")
        else:
            notify("❌ Falha na troca", f"{action} rc={r.returncode}: {r.stderr[:300]}", "x", "high")
        self._send(200 if ok else 500, (r.stdout + r.stderr).encode() or b"ok\n")
    def log_message(self, *a): pass

if __name__ == "__main__":
    if not TOKEN: log("AVISO: WEBHOOK_TOKEN vazio — endpoint SEM auth!")
    ThreadingHTTPServer((HOST, PORT), H).serve_forever()