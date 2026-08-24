#!/usr/bin/env bash
# pi-watcher — Fase 1 (READ-ONLY). O Pi watcher o VPS pela wg0 e alerta pela internet de casa.
set -euo pipefail

NTFY_URL="https://ntfy.shost.me"
NTFY_TOPIC="healthcheck"
: "${NTFY_TOKEN:?defina NTFY_TOKEN em /etc/pi-watcher/env}"

VPS_WG="10.66.66.1"
FAIL_THRESHOLD=3

STATE_DIR="/var/lib/pi-watcher"
STATE_FILE="$STATE_DIR/state"
FAIL_FILE="$STATE_DIR/failcount"
mkdir -p "$STATE_DIR"

log(){ logger -t pi-watcher -- "$*"; }
notify(){
  curl -fsS --max-time 10 -H "Authorization: Bearer ${NTFY_TOKEN}" \
    -H "Title: $1" -H "Tags: $3" -H "Priority: ${4:-default}" \
    -d "$2" "${NTFY_URL}/${NTFY_TOPIC}" >/dev/null || log "falha ao notificar"
}

if ping -c1 -W2 "$VPS_WG" >/dev/null 2>&1; then new="VPS_OK"; else new="VPS_DOWN"; fi

prev=$(cat "$STATE_FILE" 2>/dev/null || echo "VPS_OK")
fails=$(cat "$FAIL_FILE" 2>/dev/null || echo 0)

if [ "$new" = "VPS_DOWN" ]; then
  fails=$((fails + 1)); echo "$fails" > "$FAIL_FILE"
  if [ "$fails" -ge "$FAIL_THRESHOLD" ] && [ "$prev" != "VPS_DOWN" ]; then
    echo "VPS_DOWN" > "$STATE_FILE"
    log "-> VPS_DOWN"
    notify "🛑 VPS/wg0 mudo" "O Pi não alcança 10.66.66.1 pela wg0. VPS ou túnel caiu." "rotating_light" "high"
  fi
else
  echo 0 > "$FAIL_FILE"
  if [ "$prev" = "VPS_DOWN" ]; then
    log "-> VPS_OK"
    notify "✅ VPS/wg0 voltou" "O Pi alcança 10.66.66.1 de novo." "white_check_mark" "default"
  fi
  echo "VPS_OK" > "$STATE_FILE"
fi