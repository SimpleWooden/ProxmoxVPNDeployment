#!/usr/bin/env bash
# Generate WireGuard keys + client .conf files (no router access needed).
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

# Allow generate with example hostname before secrets are filled
if [[ ! -f "$CONFIG_FILE" ]]; then
  cp "${ROOT_DIR}/config.example.env" "$CONFIG_FILE"
  info "Created config.env from example - edit before apply scripts."
fi
# shellcheck disable=SC1090
set -a; source "$CONFIG_FILE"; set +a
mkdir -p "$STATE_DIR" "$CLIENTS_DIR"

[[ -f "$PEERS_FILE" ]] || cp "${ROOT_DIR}/peers.example.json" "$PEERS_FILE"

info "Generating server keypair"
server="$(wg_gen_keypair)"
server_priv="$(echo "$server" | jq -r .privateKey)"
server_pub="$(echo "$server" | jq -r .publicKey)"

peer_json='[]'
while IFS= read -r peer; do
  name="$(echo "$peer" | jq -r .name)"
  addr="$(echo "$peer" | jq -r .tunnelAddress)"
  keepalive="$(echo "$peer" | jq -r '.keepalive // 25')"
  platform="$(echo "$peer" | jq -r '.platform // "device"')"
  info "Peer $name ($addr)"
  kp="$(wg_gen_keypair)"
  priv="$(echo "$kp" | jq -r .privateKey)"
  pub="$(echo "$kp" | jq -r .publicKey)"

  conf_path="${CLIENTS_DIR}/${name}.conf"
  {
    echo "[Interface]"
    echo "PrivateKey = ${priv}"
    echo "Address = ${addr}"
    [[ -n "${WG_DNS:-}" ]] && echo "DNS = ${WG_DNS}"
    echo
    echo "[Peer]"
    echo "PublicKey = ${server_pub}"
    echo "Endpoint = ${VPN_HOSTNAME}:${WG_LISTEN_PORT}"
    echo "AllowedIPs = ${WG_LAN_CIDR}"
    echo "PersistentKeepalive = ${keepalive}"
  } >"$conf_path"

  peer_json="$(jq -c --arg n "$name" --arg a "$addr" --arg k "$keepalive" --arg p "$platform" \
    --arg pub "$pub" --arg priv "$priv" --arg conf "$conf_path" \
    '. + [{name:$n,tunnelAddress:$a,keepalive:($k|tonumber),platform:$p,publicKey:$pub,privateKey:$priv,confPath:$conf}]' \
    <<<"$peer_json")"
done < <(jq -c '.[]' "$PEERS_FILE")

jq -n \
  --arg generatedAt "$(date -Iseconds)" \
  --arg vpnHostname "$VPN_HOSTNAME" \
  --argjson listenPort "${WG_LISTEN_PORT}" \
  --arg lanCidr "$WG_LAN_CIDR" \
  --arg tunnelServer "$WG_TUNNEL_CIDR" \
  --arg instanceName "$WG_INSTANCE_NAME" \
  --arg serverPublicKey "$server_pub" \
  --arg serverPrivateKey "$server_priv" \
  --argjson peers "$peer_json" \
  '{generatedAt:$generatedAt,vpnHostname:$vpnHostname,listenPort:$listenPort,lanCidr:$lanCidr,tunnelServer:$tunnelServer,instanceName:$instanceName,serverPublicKey:$serverPublicKey,serverPrivateKey:$serverPrivateKey,peers:$peers}' \
  >"${STATE_DIR}/wireguard-keys.json"

info "Wrote ${STATE_DIR}/wireguard-keys.json"
info "Client configs in ${CLIENTS_DIR}"
info "Keep state/ and clients/ private."
