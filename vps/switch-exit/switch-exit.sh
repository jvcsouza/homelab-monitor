#!/usr/bin/env bash
# switch-exit.sh — Fase 2 (troca MANUAL assistida do exit da tabela 200)
# Uso: switch-exit.sh {residencial|datacenter|killswitch|status}
# Idempotente. Preserva o blackhole (piso) e as ip rules. NTFY_TOKEN é opcional.
set -euo pipefail

TABLE=200
IFACE_RES="wgprovider"
IFACE_DC="wgproviderdc"
LAN_NET="10.66.66.0/24"
BRAVE_NET="172.30.0.0/24"

NTFY_URL="https://ntfy.shost.me"
NTFY_TOPIC="healthcheck"
NTFY_TOKEN="${NTFY_TOKEN:-}"

log(){ logger -t switch-exit "$*"; echo "[switch-exit] $*"; }
notify(){
  [ -z "$NTFY_TOKEN" ] && return 0
  curl -fsS --max-time 10 -H "Authorization: Bearer ${NTFY_TOKEN}" \
    -H "Title: $1" -H "Tags: $3" -H "Priority: ${4:-default}" \
    -d "$2" "${NTFY_URL}/${NTFY_TOPIC}" >/dev/null || log "falha ao notificar"
}

iface_up(){ ip link show "$1" &>/dev/null; }

# Replica MASQUERADE (LAN + brave-net) e MSS clamp na interface — add-if-missing, nunca remove.
ensure_nat_mss(){
  local i="$1"
  iptables -t nat -C POSTROUTING -s "$LAN_NET"   -o "$i" -j MASQUERADE 2>/dev/null \
    || iptables -t nat -A POSTROUTING -s "$LAN_NET"   -o "$i" -j MASQUERADE
  iptables -t nat -C POSTROUTING -s "$BRAVE_NET" -o "$i" -j MASQUERADE 2>/dev/null \
    || iptables -t nat -A POSTROUTING -s "$BRAVE_NET" -o "$i" -j MASQUERADE
  iptables -t mangle -C FORWARD -o "$i" -p tcp -m tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null \
    || iptables -t mangle -A FORWARD -o "$i" -p tcp -m tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
}

activate(){
  local i="$1"
  iface_up "$i" || { log "subindo $i"; wg-quick up "$i"; }
  ensure_nat_mss "$i"                                   # NAT ANTES da rota (evita vazar sem masq)
  ip route replace default dev "$i" table "$TABLE"      # vira o default metric-0 (acima do blackhole)
  log "exit ativo -> $i"
}

status(){
  echo "== ip rule (200/210) =="; ip rule show | grep -E '^(200|210):' || true
  echo "== table $TABLE =="; ip route show table "$TABLE"
  echo "== handshakes =="
  for i in "$IFACE_RES" "$IFACE_DC"; do
    iface_up "$i" && { printf '%s: ' "$i"; wg show "$i" latest-handshakes 2>/dev/null || echo "(sem peer)"; }
  done
}

case "${1:-}" in
  residencial)
    activate "$IFACE_RES"
    notify "↩️ Exit -> residencial" "Tabela 200 default via ${IFACE_RES}." "house" "default"
    ;;
  datacenter)
    activate "$IFACE_DC"
    notify "🔁 Exit -> datacenter" "Fallback ativo: tabela 200 via ${IFACE_DC} (modo degradado)." "warning" "high"
    ;;
  killswitch)
    ip route del default dev "$IFACE_RES" table "$TABLE" 2>/dev/null || true
    ip route del default dev "$IFACE_DC"  table "$TABLE" 2>/dev/null || true
    log "KILLSWITCH: só o blackhole permanece"
    notify "🛑 Killswitch" "Sem exit vivo. Egress bloqueado (blackhole)." "rotating_light" "max"
    ;;
  status) status ;;
  *) echo "uso: $0 {residencial|datacenter|killswitch|status}"; exit 1 ;;
esac