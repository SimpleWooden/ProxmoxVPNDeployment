#!/usr/bin/env bash
# WAN UDP 51820 + WG clients to LAN via Firewall Automation API.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
load_config

WG_IF="${1:-${WG_INTERFACE:-}}"
tunnel_net="$(echo "$WG_TUNNEL_CIDR" | awk -F'[./]' '{print $1"."$2"."$3".0/24"}')"

ensure_rule() {
  local desc="$1" fields="$2"
  local search uuid body
  search="$(api GET "api/firewall/filter/searchRule?current=1&rowCount=20&searchPhrase=$(printf %s "$desc" | jq -sRr @uri)")"
  uuid="$(echo "$search" | jq -r '.rows[0].uuid // empty')"
  body="$(jq -n --argjson rule "$fields" '{rule:$rule}')"
  if [[ -n "$uuid" ]]; then
    info "Updating rule '$desc' ($uuid)"
    api POST "api/firewall/filter/setRule/${uuid}" "$body" >/dev/null
    echo "$uuid"
  else
    info "Creating rule '$desc'"
    created="$(api POST api/firewall/filter/addRule "$body")"
    uuid="$(echo "$created" | jq -r '.uuid // empty')"
    [[ -n "$uuid" ]] || die "addRule failed: $created"
    echo "$uuid"
  fi
}

wan_fields="$(jq -n --arg port "${WG_LISTEN_PORT}" \
  '{enabled:"1",sequence:"1",action:"pass",quick:"1",interface:"wan",direction:"in",ipprotocol:"inet",protocol:"UDP",source_net:"any",source_not:"0",destination_net:"(self)",destination_not:"0",destination_port:$port,log:"1",description:"Allow WireGuard WAN UDP"}')"
wan_uuid="$(ensure_rule 'Allow WireGuard WAN UDP' "$wan_fields")"

wg_uuid=""
if [[ -n "$WG_IF" ]]; then
  lan_fields="$(jq -n --arg iface "$WG_IF" --arg src "$tunnel_net" --arg dst "$WG_LAN_CIDR" \
    '{enabled:"1",sequence:"1",action:"pass",quick:"1",interface:$iface,direction:"in",ipprotocol:"inet",protocol:"any",source_net:$src,source_not:"0",destination_net:$dst,destination_not:"0",log:"0",description:"Allow WireGuard clients to LAN"}')"
  wg_uuid="$(ensure_rule 'Allow WireGuard clients to LAN' "$lan_fields")"
  dns_fields="$(jq -n --arg iface "$WG_IF" --arg src "$tunnel_net" \
    '{enabled:"1",sequence:"1",action:"pass",quick:"1",interface:$iface,direction:"in",ipprotocol:"inet",protocol:"UDP",source_net:$src,destination_net:"(self)",destination_port:"53",log:"0",description:"Allow WireGuard clients to DNS"}')"
  ensure_rule 'Allow WireGuard clients to DNS' "$dns_fields" >/dev/null
else
  info "WG_INTERFACE unset - WAN rule only. Re-run with: $0 opt1"
fi

info "Applying firewall (60s auto-rollback unless cancelled)"
sp="$(api POST api/firewall/filter/savepoint '{}')"
revision="$(echo "$sp" | jq -r .revision)"
apply="$(api POST "api/firewall/filter/apply/${revision}" '{}')"
sleep 3
if api GET api/core/firmware/status >/dev/null 2>&1; then
  api POST "api/firewall/filter/cancelRollback/${revision}" '{}' >/dev/null || true
  info "Rollback cancelled (API reachable)"
else
  echo "WARNING: Could not confirm API after apply; firewall may roll back in ~60s" >&2
fi

jq -n --arg appliedAt "$(date -Iseconds)" --arg wanRuleUuid "$wan_uuid" --arg wgRuleUuid "$wg_uuid" \
  --arg wgInterface "$WG_IF" --arg tunnelNet "$tunnel_net" --arg revision "$revision" \
  --argjson apply "$apply" \
  '{appliedAt:$appliedAt,wanRuleUuid:$wanRuleUuid,wgRuleUuid:$wgRuleUuid,wgInterface:$wgInterface,tunnelNet:$tunnelNet,revision:$revision,apply:$apply}' \
  >"${STATE_DIR}/firewall.json"
info "Saved state/firewall.json"
