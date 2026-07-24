#!/usr/bin/env bash
# Run automated helper steps in order (pauses for OPNsense UI actions).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== OPNsense WireGuard + DynDNS (helper) ==="
[[ -f "${HERE}/../config.env" ]] || {
  cp "${HERE}/../config.example.env" "${HERE}/../config.env"
  echo "Created config.env - edit it now, then re-run."
  exit 1
}
[[ -f "${HERE}/../peers.json" ]] || cp "${HERE}/../peers.example.json" "${HERE}/../peers.json"

bash "${HERE}/01-generate-peers.sh"
echo
read -r -p "Press Enter after DNS A-record + API key + os-ddclient are ready..."
bash "${HERE}/02-apply-ddns.sh"
echo
bash "${HERE}/03-apply-wireguard.sh"
echo
read -r -p "Press Enter after WireGuard interface is assigned/enabled on OPNsense..."
WG_IF="${WG_INTERFACE:-}"
if [[ -n "${1:-}" ]]; then WG_IF="$1"; fi
if [[ -n "$WG_IF" ]]; then
  bash "${HERE}/04-apply-firewall.sh" "$WG_IF"
else
  bash "${HERE}/04-apply-firewall.sh"
fi
echo
bash "${HERE}/05-export-clients.sh"
echo
bash "${HERE}/06-verify.sh" --api
echo "=== Automated portion complete - finish phone rollout + Phase 5 tests ==="
