#!/usr/bin/env bash
# Refresh client configs + rollout notes from state/wireguard-keys.json
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
# soft-load config for DNS/hostname overrides
[[ -f "$CONFIG_FILE" ]] && { set -a; source "$CONFIG_FILE"; set +a; }
keys="${STATE_DIR}/wireguard-keys.json"
[[ -f "$keys" ]] || die "Run helper/01-generate-peers.sh first"
mkdir -p "$CLIENTS_DIR"

vpn_host="$(jq -r .vpnHostname "$keys")"
port="$(jq -r .listenPort "$keys")"
lan="$(jq -r .lanCidr "$keys")"
spub="$(jq -r .serverPublicKey "$keys")"

readme="${CLIENTS_DIR}/ROLLOUT.txt"
{
  echo "WireGuard client rollout"
  echo "========================"
  echo
  echo "1. Install official WireGuard app (phone or PC)."
  echo "2. Phones: scan QR in OPNsense (VPN -> WireGuard -> Peers) or import .conf"
  echo "3. PCs: WireGuard -> Import tunnel from file -> Activate."
  echo "4. Name tunnel Home. Test on cellular: ping 10.10.10.1 and 192.168.0.1"
  echo
  echo "Endpoint: ${vpn_host}:${port}"
  echo "LAN routes: ${lan}"
  echo
  echo "Configs:"
} >"$readme"

while IFS= read -r peer; do
  name="$(echo "$peer" | jq -r .name)"
  addr="$(echo "$peer" | jq -r .tunnelAddress)"
  priv="$(echo "$peer" | jq -r .privateKey)"
  ka="$(echo "$peer" | jq -r .keepalive)"
  conf="${CLIENTS_DIR}/${name}.conf"
  {
    echo "[Interface]"
    echo "PrivateKey = ${priv}"
    echo "Address = ${addr}"
    [[ -n "${WG_DNS:-}" ]] && echo "DNS = ${WG_DNS}"
    echo
    echo "[Peer]"
    echo "PublicKey = ${spub}"
    echo "Endpoint = ${vpn_host}:${port}"
    echo "AllowedIPs = ${lan}"
    echo "PersistentKeepalive = ${ka}"
  } >"$conf"
  echo "  - ${name}: ${conf}" >>"$readme"
done < <(jq -c '.peers[]' "$keys")

echo >>"$readme"
echo "Security: one peer per device. Revoke lost devices by disabling that peer only." >>"$readme"
cat "$readme"
