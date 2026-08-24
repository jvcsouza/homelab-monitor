#!/usr/bin/env bash
# switch-exit.sh — Fase 2 (troca MANUAL do exit da tabela 200)
# Plumbing (NAT/MSS/forward) é PERMANENTE via UFW; este script só vira a ROTA.
# Uso: switch-exit.sh {residencial|datacenter|killswitch|status}
set -euo pipefail

TABLE=200
IFACE_RES="wgprovider"
IFACE_DC="wgproviderdc"

NTFY_URL="https://ntfy.shost.me"
NTFY_TOPIC="healthcheck"
NTFY_TOKEN="${NTFY_TOKEN:-}"

log(){ logger -t switch-exit -- "$*"; echo "[switch-exit] $*"; }
notify(){
  [ -z "$NTFY_TOKEN" ] && return 0
  curl -fsS --max-time 10 -H "Authorization: Bearer ${NTFY_TOKEN}" \
    -H "Title: $1" -H "Tags: $3" -H "Priority: ${4:-default}" \
    -d "$2" "${NTFY_URL}/${NTFY_TOPIC}" >/dev/null || log "falha ao notificar"
}

iface_up(){ ip link show "$1" &>/dev/null; }

activate(){
  local i="$1"
  iface_up "$i" || { log "subindo $i"; wg-quick up "$i"; }
  ip route replace default dev "$i" table "$TABLE"   # default metric-0 (acima do blackhole)
  log "exit ativo -> $i"
}

status(){
  echo "== table $TABLE =="; ip route show table "$TABLE"
  echo "== forward (ufw-user-forward) =="; iptables -S ufw-user-forward 2>/dev/null | grep -E 'wgprovider' || echo "(nenhuma)"
  echo "== nat POSTROUTING =="; iptables -t nat -S POSTROUTING | grep -E 'wgprovider' || echo "(nenhuma)"
  echo "== handshakes =="
  for i in "$IFACE_RES" "$IFACE_DC"; do
    iface_up "$i" && { printf '%s: ' "$i"; wg show "$i" latest-handshakes 2>/dev/null; }
  done
}

case "${1:-}" in
  residencial) activate "$IFACE_RES"; notify "↩️ Exit -> residencial" "Tabela 200 via ${IFACE_RES}." "house" "default" ;;
  datacenter)  activate "$IFACE_DC";  notify "🔁 Exit -> datacenter" "Fallback ativo via ${IFACE_DC} (modo degradado)." "warning" "high" ;;
  killswitch)
    ip route del default dev "$IFACE_RES" table "$TABLE" 2>/dev/null || true
    ip route del default dev "$IFACE_DC"  table "$TABLE" 2>/dev/null || true
    log "KILLSWITCH: só o blackhole permanece"
    notify "🛑 Killswitch" "Sem exit vivo. Egress bloqueado (blackhole)." "rotating_light" "max" ;;
  status) status ;;
  *) echo "uso: $0 {residencial|datacenter|killswitch|status}"; exit 1 ;;
esac