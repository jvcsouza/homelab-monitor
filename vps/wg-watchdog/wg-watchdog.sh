#!/usr/bin/env bash
# wg-watchdog — Fase 2.5. Detecta exit residencial (idade do handshake) e notifica
# COM botões de ação (se WEBHOOK_URL/TOKEN estiverem no env; senão, alerta simples).
set -euo pipefail

NTFY_URL="https://ntfy.shost.me"
NTFY_TOPIC="healthcheck"
: "${NTFY_TOKEN:?defina NTFY_TOKEN em /etc/wg-watchdog/env}"
WEBHOOK_URL="${WEBHOOK_URL:-}"       # ex http://10.66.66.1:8088 (vazio = sem botão)
WEBHOOK_TOKEN="${WEBHOOK_TOKEN:-}"

IFACE_RES="wgprovider"
HANDSHAKE_MAX=180
FAIL_THRESHOLD=3

STATE_DIR="/var/lib/wg-watchdog"
STATE_FILE="$STATE_DIR/state"
FAIL_FILE="$STATE_DIR/failcount"
mkdir -p "$STATE_DIR"

log(){ logger -t wg-watchdog -- "$*"; }

# publica via JSON (suporta actions). $1 = corpo JSON completo
publish(){ curl -fsS --max-time 10 -H "Authorization: Bearer ${NTFY_TOKEN}" \
  -H "Content-Type: application/json" -d "$1" "$NTFY_URL" >/dev/null || log "falha ao notificar"; }

# monta uma action http; string vazia se webhook não configurado
mk_action(){   # $1=label  $2=path
  if [ -z "$WEBHOOK_URL" ] || [ -z "$WEBHOOK_TOKEN" ]; then echo ""; return 0; fi
  printf '{"action":"http","label":"%s","url":"%s%s","method":"POST","headers":{"Authorization":"Bearer %s"},"clear":true}' \
    "$1" "$WEBHOOK_URL" "$2" "$WEBHOOK_TOKEN"
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
    act=$(mk_action "🔁 Trocar pra DC" "/datacenter"); acts="[]"; [ -n "$act" ] && acts="[$act]"
    publish "$(printf '{"topic":"%s","title":"⚠️ Exit residencial caiu","message":"Handshake parado há %ss. Trocar pra datacenter?","priority":5,"tags":["rotating_light"],"actions":%s}' "$NTFY_TOPIC" "$age" "$acts")"
  fi
else
  echo 0 > "$FAIL_FILE"
  if [ "$prev" = "RESIDENCIAL_DOWN" ]; then
    log "-> RESIDENCIAL_OK"
    act=$(mk_action "↩️ Voltar pro residencial" "/residencial"); acts="[]"; [ -n "$act" ] && acts="[$act]"
    publish "$(printf '{"topic":"%s","title":"✅ Exit residencial voltou","message":"Handshake fresco (%ss). Voltar o exit pro residencial?","priority":3,"tags":["white_check_mark"],"actions":%s}' "$NTFY_TOPIC" "$age" "$acts")"
  fi
  echo "RESIDENCIAL_OK" > "$STATE_FILE"
fi