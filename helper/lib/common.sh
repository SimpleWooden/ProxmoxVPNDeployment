#!/usr/bin/env bash
# Shared helpers for OPNsense API + WireGuard keygen (Alpine/Debian).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATE_DIR="${ROOT_DIR}/state"
CLIENTS_DIR="${ROOT_DIR}/clients"
CONFIG_FILE="${ROOT_DIR}/config.env"
PEERS_FILE="${ROOT_DIR}/peers.json"

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "==> $*"; }

load_config() {
  [[ -f "$CONFIG_FILE" ]] || die "Missing $CONFIG_FILE - copy config.example.env and edit it."
  # shellcheck disable=SC1090
  set -a; source "$CONFIG_FILE"; set +a
  [[ -n "${OPNSENSE_URL:-}" ]] || die "OPNSENSE_URL required"
  [[ -n "${OPNSENSE_API_KEY:-}" ]] || die "OPNSENSE_API_KEY required"
  [[ -n "${OPNSENSE_API_SECRET:-}" ]] || die "OPNSENSE_API_SECRET required"
  [[ "$OPNSENSE_API_KEY" != PASTE_* ]] || die "Replace PASTE_ placeholders in config.env"
  [[ -n "${VPN_HOSTNAME:-}" ]] || die "VPN_HOSTNAME required"
  mkdir -p "$STATE_DIR" "$CLIENTS_DIR"
}

api() {
  local method="$1" path="$2" data="${3:-}"
  local url="${OPNSENSE_URL%/}/${path#/}"
  local args=(-sS -u "${OPNSENSE_API_KEY}:${OPNSENSE_API_SECRET}" -H 'Accept: application/json' -X "$method")
  [[ "${OPNSENSE_INSECURE:-1}" == "1" ]] && args+=(-k)
  if [[ -n "$data" ]]; then
    args+=(-H 'Content-Type: application/json' -d "$data")
  fi
  curl "${args[@]}" "$url"
}

resolve_dyndns_service() {
  if [[ -n "${DYNDNS_SERVICE:-}" ]]; then
    echo "$DYNDNS_SERVICE"
    return
  fi
  case "${DYNDNS_PROVIDER,,}" in
    cloudflare) echo Cloudflare ;;
    namecheap)  echo NameCheap ;;
    duckdns)    echo 'Duck DNS' ;;
    godaddy)    echo GoDaddy ;;
    dynu)       echo Dynu ;;
    noip)       echo no-ip ;;
    *) die "Unknown DYNDNS_PROVIDER='$DYNDNS_PROVIDER'. Set DYNDNS_SERVICE to the exact OPNsense label." ;;
  esac
}

wg_gen_keypair() {
  if command -v wg >/dev/null 2>&1; then
    local priv pub
    priv="$(wg genkey)"
    pub="$(printf '%s' "$priv" | wg pubkey)"
    printf '{"privateKey":"%s","publicKey":"%s"}\n' "$priv" "$pub"
    return
  fi
  die "wireguard tools (wg) not installed"
}

json_get() {
  # Usage: json_get FILE jq_filter
  local file="$1" filter="$2"
  if command -v jq >/dev/null 2>&1; then
    jq -r "$filter" "$file"
  else
    die "jq is required"
  fi
}
