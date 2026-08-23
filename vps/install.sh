#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # .../vps
WD="$HERE/wg-watchdog"

# --- env (segredo, fora do git) ---
if [ ! -f /etc/wg-watchdog/env ]; then
  sudo mkdir -p /etc/wg-watchdog
  sudo cp "$WD/env.example" /etc/wg-watchdog/env
  sudo chmod 600 /etc/wg-watchdog/env
  echo ">> Criado /etc/wg-watchdog/env — edite e coloque o NTFY_TOKEN."
fi

# --- units systemd apontando pro script DESTE repo ---
sudo tee /etc/systemd/system/wg-watchdog.service >/dev/null <<UNIT
[Unit]
Description=WireGuard exit watchdog (Fase 1, read-only)
After=network-online.target
[Service]
Type=oneshot
EnvironmentFile=/etc/wg-watchdog/env
ExecStart=$WD/wg-watchdog.sh
UNIT

sudo tee /etc/systemd/system/wg-watchdog.timer >/dev/null <<UNIT
[Unit]
Description=Roda o wg-watchdog periodicamente
[Timer]
OnBootSec=60
OnUnitActiveSec=45
[Install]
WantedBy=timers.target
UNIT

chmod +x "$WD/wg-watchdog.sh"
sudo systemctl daemon-reload
sudo systemctl enable --now wg-watchdog.timer
echo ">> wg-watchdog.timer ativo. Logs: journalctl -t wg-watchdog -f"
