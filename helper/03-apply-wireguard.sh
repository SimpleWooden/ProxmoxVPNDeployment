#!/usr/bin/env bash
# Create WireGuard instance + peers on OPNsense from state/wireguard-keys.json
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
load_config

keys="${STATE_DIR}/wireguard-keys.json"
[[ -f "$keys" ]] || die "Missing state/wireguard-keys.json - run helper/01-generate-peers.sh first"

info "Enabling WireGuard service"
api POST api/wireguard/general/set '{"general":{"enabled":"1"}}' >/dev/null || true

peer_uuids=()
peer_map='[]'
while IFS= read -r peer; do
  name="$(echo "$peer" | jq -r .name)"
  pub="$(echo "$peer" | jq -r .publicKey)"
  addr="$(echo "$peer" | jq -r .tunnelAddress)"
  keepalive="$(echo "$peer" | jq -r .keepalive)"
  info "Ensuring peer $name"
  search="$(api GET "api/wireguard/client/searchClient?current=1&rowCount=50&searchPhrase=$(printf %s "$name" | jq -sRr @uri)")"
  body="$(jq -n --arg name "$name" --arg pub "$pub" --arg addr "$addr" --arg ka "$keepalive" \
    '{client:{enabled:"1",name:$name,pubkey:$pub,psk:"",tunneladdress:$addr,serveraddress:"",serverport:"",keepalive:$ka,persistentkeepalive:$ka,endpoint:"",endpointport:"",servers:""}}')"
  uuid="$(echo "$search" | jq -r '.rows[0].uuid // empty')"
  if [[ -n "$uuid" ]]; then
    api POST "api/wireguard/client/setClient/${uuid}" "$body" >/dev/null
  else
    created="$(api POST api/wireguard/client/addClient "$body")"
    echo "$created" | jq -e '.result != "failed"' >/dev/null || die "addClient failed: $created"
    uuid="$(echo "$created" | jq -r .uuid)"
  fi
  peer_uuids+=("$uuid")
  peer_map="$(jq -c --arg n "$name" --arg u "$uuid" --arg a "$addr" '. + [{name:$n,uuid:$u,tunnelAddress:$a}]' <<<"$peer_map")"
done < <(jq -c '.peers[]' "$keys")

peers_csv="$(IFS=,; echo "${peer_uuids[*]}")"
iname="$(jq -r .instanceName "$keys")"
info "Ensuring WireGuard instance $iname"
srv_search="$(api GET "api/wireguard/server/searchServer?current=1&rowCount=50&searchPhrase=$(printf %s "$iname" | jq -sRr @uri)")"
server_body="$(jq -n \
  --arg name "$iname" \
  --arg pub "$(jq -r .serverPublicKey "$keys")" \
  --arg priv "$(jq -r .serverPrivateKey "$keys")" \
  --arg tunnel "$(jq -r .tunnelServer "$keys")" \
  --arg port "$(jq -r .listenPort "$keys")" \
  --arg peers "$peers_csv" \
  --arg dns "${WG_DNS:-}" \
  '{server:{enabled:"1",name:$name,pubkey:$pub,privkey:$priv,tunneladdress:$tunnel,port:$port,peers:$peers,dns:$dns,mtu:"",disableroutes:"0",gateway:"",carp_depend_on:""}}')"

server_uuid="$(echo "$srv_search" | jq -r '.rows[0].uuid // empty')"
if [[ -n "$server_uuid" ]]; then
  setr="$(api POST "api/wireguard/server/setServer/${server_uuid}" "$server_body")"
  echo "$setr" | jq -e '.result != "failed"' >/dev/null || die "setServer failed: $setr"
else
  created="$(api POST api/wireguard/server/addServer "$server_body")"
  echo "$created" | jq -e '.result != "failed"' >/dev/null || die "addServer failed: $created"
  server_uuid="$(echo "$created" | jq -r .uuid)"
fi

info "Reconfigure WireGuard"
reconf="$(api POST api/wireguard/service/reconfigure '{}')"
jq -n --arg appliedAt "$(date -Iseconds)" --arg serverUuid "$server_uuid" \
  --argjson peerUuids "$peer_map" --argjson reconfigure "$reconf" \
  '{appliedAt:$appliedAt,serverUuid:$serverUuid,peerUuids:$peerUuids,reconfigure:$reconfigure}' \
  >"${STATE_DIR}/wireguard-applied.json"

cat <<EOF
Saved state/wireguard-applied.json

MANUAL (required on OPNsense):
  Interfaces -> Assignments -> add WireGuard device (wg0/wt0)
  Enable interface, Apply.
  Then: helper/04-apply-firewall.sh
EOF
