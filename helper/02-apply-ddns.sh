#!/usr/bin/env bash
# Apply DynDNS account on OPNsense via API.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
load_config

service="$(resolve_dyndns_service)"
info "Enabling DynDNS general settings"
api POST api/dyndns/settings/set "$(jq -n \
  --arg delay "${DYNDNS_INTERVAL}" \
  '{general:{enabled:"1",verbose:"0",allowipv6:"0",daemon_delay:$delay,backend:"native"}}')" >/dev/null

info "Searching existing accounts for ${VPN_HOSTNAME}"
search="$(api GET "api/dyndns/accounts/searchItem?current=1&rowCount=50&searchPhrase=$(printf %s "$VPN_HOSTNAME" | jq -sRr @uri)")"

body="$(jq -n \
  --arg desc "VPN ${VPN_HOSTNAME}" \
  --arg service "$service" \
  --arg user "${DYNDNS_USERNAME}" \
  --arg pass "${DYNDNS_PASSWORD}" \
  --arg zone "${DNS_ZONE}" \
  --arg host "${VPN_HOSTNAME}" \
  --arg checkip "${DYNDNS_CHECKIP}" \
  --arg iface "${DYNDNS_INTERFACE}" \
  '{account:{enabled:"1",description:$desc,service:$service,username:$user,password:$pass,zone:$zone,hostnames:$host,wildcard:"0",checkip:$checkip,interface:$iface,checkip_timeout:"10",force_ssl:"1"}}')"

uuid="$(echo "$search" | jq -r '.rows[0].uuid // empty')"
if [[ -n "$uuid" ]]; then
  info "Updating account $uuid"
  result="$(api POST "api/dyndns/accounts/setItem/${uuid}" "$body")"
else
  info "Creating DynDNS account ($service)"
  result="$(api POST api/dyndns/accounts/addItem "$body")"
  uuid="$(echo "$result" | jq -r '.uuid // empty')"
fi

info "Reconfigure DynDNS"
reconf="$(api POST api/dyndns/service/reconfigure '{}')"
status="$(api GET api/dyndns/service/status)"

jq -n --arg appliedAt "$(date -Iseconds)" --arg hostname "$VPN_HOSTNAME" --arg zone "$DNS_ZONE" \
  --arg service "$service" --arg accountUuid "$uuid" \
  --argjson reconfigure "$reconf" --argjson status "$status" --argjson apiResult "$result" \
  '{appliedAt:$appliedAt,hostname:$hostname,zone:$zone,service:$service,accountUuid:$accountUuid,reconfigure:$reconfigure,status:$status,apiResult:$apiResult}' \
  >"${STATE_DIR}/ddns.json"

info "Saved state/ddns.json - verify Services -> Dynamic DNS Current IP"
