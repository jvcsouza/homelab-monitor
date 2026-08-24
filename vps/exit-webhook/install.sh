#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY="$HERE/exit-webhook.py"
SWITCH="/opt/homelab-monitor/vps/switch-exit/switch-exit.sh"
SVCUSER="exithook"

# usuário de serviço sem login
id "$SVCUSER" &>/dev/null || sudo useradd --system --no-create-home --shell /usr/sbin/nologin "$SVCUSER"

# env (segredo)
if [ ! -f /etc/exit-webhook/env ]; then
  sudo mkdir -p /etc/exit-webhook
  sudo cp "$HERE/env.example" /etc/exit-webhook/env
  sudo chmod 600 /etc/exit-webhook/env
  echo ">> Criado /etc/exit-webhook/env — edite WEBHOOK_TOKEN e NTFY_TOKEN."
fi

# sudoers: exithook roda SÓ o switch com args fixos (least-privilege)
sudo tee /etc/sudoers.d/exit-webhook >/dev/null <<SUDO
Defaults:${SVCUSER} !requiretty
${SVCUSER} ALL=(root) NOPASSWD: ${SWITCH} datacenter, ${SWITCH} residencial, ${SWITCH} killswitch
SUDO
sudo chmod 440 /etc/sudoers.d/exit-webhook
sudo visudo -cf /etc/sudoers.d/exit-webhook

chmod +x "$SWITCH" "$PY" 2>/dev/null || true

# systemd unit
sudo tee /etc/systemd/system/exit-webhook.service >/dev/null <<UNIT
[Unit]
Description=Webhook de troca de exit (Fase 2.5)
After=network-online.target
[Service]
User=${SVCUSER}
EnvironmentFile=/etc/exit-webhook/env
ExecStart=/usr/bin/python3 ${PY}
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
UNIT

# libera a porta SÓ pela wg0
PORT="$(grep -oP '(?<=WEBHOOK_PORT=).*' /etc/exit-webhook/env 2>/dev/null || echo 8088)"
sudo ufw allow in on wg0 to any port "$PORT" proto tcp || true

sudo systemctl daemon-reload
sudo systemctl enable --now exit-webhook.service
echo ">> exit-webhook ativo. Logs: journalctl -u exit-webhook -f"