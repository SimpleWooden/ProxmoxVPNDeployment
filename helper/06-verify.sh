#!/usr/bin/env bash
# Local verification: DNS + optional API checks + IP-change test reminders.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

CHECK_API=0
[[ "${1:-}" == "--api" ]] && CHECK_API=1

if [[ -f "$CONFIG_FILE" ]]; then
  load_config
else
  die "Missing config.env"
fi

info "DNS lookup for ${VPN_HOSTNAME}"
if getent hosts "$VPN_HOSTNAME" >/dev/null 2>&1; then
  getent hosts "$VPN_HOSTNAME" | awk '{print "    "$1}'
elif command -v dig >/dev/null 2>&1; then
  dig +short "$VPN_HOSTNAME" A || true
else
  echo "    (install bind-tools/dnsutils for dig, or check from your PC)"
fi

if [[ "$CHECK_API" -eq 1 ]]; then
  info "DynDNS status"
  api GET api/dyndns/service/status | jq -c . || true
  info "WireGuard status"
  api GET api/wireguard/service/status | jq -c . || api GET api/wireguard/service/show | jq -c . || true
fi

cat <<EOF

Manual IP-change test:
  1. Note WAN IP in OPNsense Interfaces -> Overview
  2. Phone on cellular: enable Home WireGuard tunnel
  3. Ping 10.10.10.1 and 192.168.0.1
  4. Renew WAN DHCP / wait for DynDNS; confirm A record updates
  5. Toggle tunnel - should reconnect via ${VPN_HOSTNAME}

See checklist/MANUAL-STEPS.md
EOF
