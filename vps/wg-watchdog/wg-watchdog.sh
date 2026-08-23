#!/usr/bin/env bash
# wg-watchdog — Fase 1 (READ-ONLY). Detecta exit residencial morto via idade do handshake.
set -euo pipefail

NTFY_URL="https://ntfy.shost.me"
NTFY_TOPIC="healthcheck"
: "${NTFY_TOKEN:?defina NTFY_TOKEN em /etc/wg-watchdog/env}"

IFACE_RES="wgprovider"
HANDSHAKE_MAX=180        # s; handshake mais velho = exit morto
FAIL_THRESHOLD=3         # histerese

STATE_DIR="/var/lib/wg-watchdog"
STATE_FILE="$STATE_DIR/state"
FAIL_FILE="$STATE_DIR/failcount"
mkdir -p "$STATE_DIR"

log(){ logger -t wg-watchdog "$*"; }
notify(){
  curl -fsS --max-time 10 -H "Authorization: Bearer ${NTFY_TOKEN}" \
    -H "Title: $1" -H "Tags: $3" -H "Priority: ${4:-default}" \
    -d "$2" "${NTFY_URL}/${NTFY_TOPIC}" >/dev/null || log "falha ao notificar"
}

handshake_age(){
  local ts now
  ts=$(wg show "$IFACE_RES" latest-handshakes 2>/dev/null | awk 'NR==1{print $2}') || true
  if [ -z "${ts:-}" ] || [ "$ts" = "0" ]; then echo 999999; return 0; fi
  now=$(date +%s); echo $(( now - ts ))
}

age=$(handshake_age)
if [ "$age" -le "$HANDSHAKE_MAX" ]; then new="RESIDENCIAL_OK"; else new="RESIDENCIAL_DOWN"; fi

prev=$(cat "$STATE_FILE" 2>/dev/null || echo "RESIDENCIAL_OK")
fails=$(cat "$FAIL_FILE" 2>/dev/null || echo 0)

if [ "$new" = "RESIDENCIAL_DOWN" ]; then
  fails=$((fails + 1)); echo "$fails" > "$FAIL_FILE"
  if [ "$fails" -ge "$FAIL_THRESHOLD" ] && [ "$prev" != "RESIDENCIAL_DOWN" ]; then
    echo "RESIDENCIAL_DOWN" > "$STATE_FILE"
    log "-> RESIDENCIAL_DOWN (handshake ${age}s)"
    notify "⚠️ Exit residencial caiu" "Handshake do wgprovider parado há ${age}s. Candidato a fallback datacenter." "warning,rotating_light" "high"
  fi
else
  echo 0 > "$FAIL_FILE"
  if [ "$prev" = "RESIDENCIAL_DOWN" ]; then
    log "-> RESIDENCIAL_OK"
    notify "✅ Exit residencial voltou" "Handshake do wgprovider fresco (${age}s)." "white_check_mark" "default"
  fi
  echo "RESIDENCIAL_OK" > "$STATE_FILE"
fi
