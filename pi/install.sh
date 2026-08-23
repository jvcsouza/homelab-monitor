#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # .../pi
PV="$HERE/pi-watcher"

if [ ! -f /etc/pi-watcher/env ]; then
  sudo mkdir -p /etc/pi-watcher
  sudo cp "$PV/env.example" /etc/pi-watcher/env
  sudo chmod 600 /etc/pi-watcher/env
  echo ">> Criado /etc/pi-watcher/env — edite e coloque o NTFY_TOKEN."
fi

sudo tee /etc/systemd/system/pi-watcher.service >/dev/null <<UNIT
[Unit]
Description=Pi watcher do VPS/wg0 (Fase 1, read-only)
After=network-online.target
[Service]
Type=oneshot
EnvironmentFile=/etc/pi-watcher/env
ExecStart=$PV/pi-watcher.sh
UNIT

sudo tee /etc/systemd/system/pi-watcher.timer >/dev/null <<UNIT
[Unit]
Description=Roda o pi-watcher periodicamente
[Timer]
OnBootSec=60
OnUnitActiveSec=60
[Install]
WantedBy=timers.target
UNIT

chmod +x "$PV/pi-watcher.sh"
sudo systemctl daemon-reload
sudo systemctl enable --now pi-watcher.timer
echo ">> pi-watcher.timer ativo. Logs: journalctl -t pi-watcher -f"
