#!/usr/bin/env bash
# Proxmox Deployment Helper — interactive wizard
# Creates a minimal Alpine LXC that configures OPNsense WireGuard + DynDNS.
#
# IMPORTANT: do NOT use  bash -c "$(curl ...)"  — that expands $(...) too early.
# Use one of:
#   bash <(curl -fsSL https://raw.githubusercontent.com/SimpleWooden/ProxmoxVPNDeployment/main/proxmox/create-helper-ct.sh)
#   curl -fsSL ... -o /tmp/create-helper-ct.sh && bash /tmp/create-helper-ct.sh

set -euo pipefail

REPO_URL_DEFAULT="https://github.com/SimpleWooden/ProxmoxVPNDeployment.git"
RAW_BASE="https://raw.githubusercontent.com/SimpleWooden/ProxmoxVPNDeployment/main"

# --------------- colors ---------------
if [[ -t 1 ]]; then
  C_BLD='\033[1m'; C_GRN='\033[0;32m'; C_CYN='\033[0;36m'
  C_YEL='\033[1;33m'; C_RED='\033[0;31m'; C_RST='\033[0m'
else
  C_BLD=''; C_GRN=''; C_CYN=''; C_YEL=''; C_RED=''; C_RST=''
fi

die()  { echo -e "${C_RED}ERROR:${C_RST} $*" >&2; exit 1; }
info() { echo -e "${C_CYN}==>${C_RST} $*"; }
ok()   { echo -e "${C_GRN}OK:${C_RST} $*"; }
need() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1 (run as root on the Proxmox host)"; }

prompt() {
  # prompt VAR "Label" "default"
  local __var="$1" __label="$2" __default="${3:-}" __reply=""
  if [[ -n "$__default" ]]; then
    read -r -p "$(echo -e "${C_BLD}${__label}${C_RST} [${__default}]: ")" __reply || true
    printf -v "$__var" '%s' "${__reply:-$__default}"
  else
    read -r -p "$(echo -e "${C_BLD}${__label}${C_RST}: ")" __reply || true
    printf -v "$__var" '%s' "$__reply"
  fi
}

confirm() {
  local __reply=""
  read -r -p "$(echo -e "${C_YEL}$*${C_RST} [Y/n]: ")" __reply || true
  case "${__reply:-Y}" in
    Y|y|yes|YES|"") return 0 ;;
    *) return 1 ;;
  esac
}

banner() {
  clear 2>/dev/null || true
  cat <<'BANNER'
============================================================
  Proxmox VPN Deployment Helper
  Alpine LXC -> configures OPNsense WireGuard + DynDNS
============================================================
BANNER
  echo -e "VPN terminates on ${C_BLD}OPNsense${C_RST}; this CT is only the config helper."
  echo -e "Default footprint: ${C_BLD}1 vCPU / 128 MB RAM / 1 GB disk${C_RST}"
  echo
}

[[ "$(id -u)" -eq 0 ]] || die "Run as root on the Proxmox host"
need pct
need pvesm
need pveam
need wget
need git
need awk

banner

# Next free CTID starting at 200
NEXT_ID=200
while pct status "$NEXT_ID" &>/dev/null; do NEXT_ID=$((NEXT_ID + 1)); done

# Prefer app-storage when present; otherwise first rootdir-capable store
DEFAULT_STORAGE="app-storage"
if ! pvesm status -content rootdir 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx "app-storage"; then
  DEFAULT_STORAGE="$(pvesm status -content rootdir 2>/dev/null | awk 'NR>1 && $2!="dir" {print $1; exit}')"
  [[ -n "$DEFAULT_STORAGE" ]] || DEFAULT_STORAGE="$(pvesm status -content rootdir 2>/dev/null | awk 'NR>1 {print $1; exit}')"
  [[ -n "$DEFAULT_STORAGE" ]] || DEFAULT_STORAGE="app-storage"
fi

# Bridges hint
BRIDGE_HINT="$(ls /sys/class/net 2>/dev/null | grep -E '^vmbr' | head -n1 || true)"
[[ -n "$BRIDGE_HINT" ]] || BRIDGE_HINT="vmbr0"

echo -e "${C_BLD}Container settings${C_RST}"
echo "-------------------"
prompt CTID            "CTID"            "$NEXT_ID"
prompt CT_HOSTNAME     "Hostname"        "BTAL01"
prompt STORAGE         "Storage"         "$DEFAULT_STORAGE"
prompt BRIDGE          "Bridge"          "$BRIDGE_HINT"
prompt STATIC_IP       "Static IPv4"     "192.168.0.122"
prompt CIDR            "CIDR prefix"     "22"
prompt GATEWAY         "Gateway"         "192.168.0.1"
prompt NAMESERVER      "DNS nameserver"  "192.168.0.1"
prompt CORES           "CPU cores"       "1"
prompt MEMORY_MB       "Memory (MB)"     "128"
prompt SWAP_MB         "Swap (MB)"       "128"
prompt DISK_GB         "Disk (GB)"       "1"
prompt TEMPLATE_STORAGE "Template storage" "local"
prompt ALPINE_VERSION  "Alpine major"    "3.21"
prompt REPO_URL        "Git repo URL"    "$REPO_URL_DEFAULT"
prompt REPO_REF        "Git branch"      "main"
prompt PASSWORD        "CT root password (empty=random)" ""

if [[ -z "$PASSWORD" ]]; then
  PASSWORD="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20)"
  GENERATED_PW=1
else
  GENERATED_PW=0
fi

IPCONFIG="ip=${STATIC_IP}/${CIDR},gw=${GATEWAY}"

echo
echo -e "${C_BLD}Summary${C_RST}"
echo "-------"
echo "  CTID:      $CTID"
echo "  Hostname:  $CT_HOSTNAME"
echo "  Storage:   $STORAGE"
echo "  Network:   $BRIDGE  $IPCONFIG"
echo "  DNS:       $NAMESERVER"
echo "  Resources: ${CORES} vCPU / ${MEMORY_MB}M RAM / ${DISK_GB}G disk"
echo "  Repo:      $REPO_URL ($REPO_REF)"
echo
confirm "Create container now?" || die "Aborted by user."

pct status "$CTID" &>/dev/null && die "CTID $CTID already exists. Choose another ID."

info "Updating appliance list (pveam)..."
pveam update >/dev/null 2>&1 || true

info "Selecting Alpine ${ALPINE_VERSION} template..."
TEMPLATE="$(pveam available -section system 2>/dev/null | awk -v v="$ALPINE_VERSION" '$2 ~ ("alpine-" v) && $2 ~ /default/ {print $2; exit}')"
[[ -n "$TEMPLATE" ]] || TEMPLATE="$(pveam available -section system 2>/dev/null | awk '/alpine-.*-default/ {print $2; exit}')"
[[ -n "$TEMPLATE" ]] || die "No Alpine template found via pveam. Download one under local storage -> CT Templates."

if ! pveam list "$TEMPLATE_STORAGE" 2>/dev/null | awk '{print $1}' | grep -qx "$TEMPLATE"; then
  info "Downloading template $TEMPLATE (this can take a minute)..."
  pveam download "$TEMPLATE_STORAGE" "$TEMPLATE"
else
  ok "Template already present: $TEMPLATE"
fi
TEMPLATE_PATH="${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}"

info "Creating CT ${CTID} (${CT_HOSTNAME})..."
pct create "$CTID" "$TEMPLATE_PATH" \
  --hostname "$CT_HOSTNAME" \
  --cores "$CORES" \
  --memory "$MEMORY_MB" \
  --swap "$SWAP_MB" \
  --rootfs "${STORAGE}:${DISK_GB}" \
  --net0 "name=eth0,bridge=${BRIDGE},${IPCONFIG}" \
  --nameserver "$NAMESERVER" \
  --unprivileged 1 \
  --features nesting=0 \
  --onboot 0 \
  --password "$PASSWORD" \
  --start 0

info "Starting CT ${CTID}..."
pct start "$CTID"
sleep 4

info "Installing packages inside CT..."
pct exec "$CTID" -- sh -c '
  set -e
  if [ -f /etc/apk/repositories ]; then
    sed -i "s/^#\s*\(.*\/community\)/\1/" /etc/apk/repositories || true
    apk update
    apk add --no-cache bash curl jq wireguard-tools-wg git ca-certificates bind-tools nano
  elif command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq bash curl jq wireguard-tools git ca-certificates dnsutils nano
  else
    echo "Unsupported CT OS"; exit 1
  fi
'

HELPER_DIR="/opt/opnsense-wg-helper"
TMP_CLONE="$(mktemp -d)"
cleanup() { rm -rf "$TMP_CLONE"; }
trap cleanup EXIT

info "Cloning helper repo into CT..."
git clone --depth 1 --branch "$REPO_REF" "$REPO_URL" "$TMP_CLONE/repo"
pct exec "$CTID" -- mkdir -p "$HELPER_DIR"
tar -C "$TMP_CLONE/repo" -cf - . | pct exec "$CTID" -- tar -C "$HELPER_DIR" -xf -
pct exec "$CTID" -- sh -c "chmod +x ${HELPER_DIR}/helper/*.sh ${HELPER_DIR}/proxmox/*.sh 2>/dev/null || true"
pct exec "$CTID" -- sh -c "
  cd ${HELPER_DIR}
  cp -n config.example.env config.env 2>/dev/null || true
  cp -n peers.example.json peers.json 2>/dev/null || true
"

pct exec "$CTID" -- sh -c "cat > /usr/local/bin/opn-wg-configure <<'EOF'
#!/bin/sh
cd /opt/opnsense-wg-helper && exec bash helper/configure.sh \"\$@\"
EOF
chmod +x /usr/local/bin/opn-wg-configure"

CT_IP="$(pct exec "$CTID" -- sh -c "ip -4 -o addr show eth0 2>/dev/null | awk '{print \$4}' | cut -d/ -f1 | head -n1" || true)"
[[ -n "$CT_IP" ]] || CT_IP="$STATIC_IP"

echo
ok "Container ready"
cat <<EOF

============================================================
  CTID:       ${CTID}
  Hostname:   ${CT_HOSTNAME}
  IP:         ${CT_IP}
  Bridge:     ${BRIDGE}
  Resources:  ${CORES} vCPU / ${MEMORY_MB} MB / ${DISK_GB} GB
  Path:       ${HELPER_DIR}
$([ "$GENERATED_PW" -eq 1 ] && echo "  root pass:  ${PASSWORD}" || echo "  root pass:  (as you set)")
============================================================

Next:
  1) pct enter ${CTID}
  2) nano ${HELPER_DIR}/config.env
  3) nano ${HELPER_DIR}/peers.json
  4) On OPNsense: backup, os-ddclient, API key, DNS A-record
  5) opn-wg-configure
     then after WG interface assign: opn-wg-configure opt1

Docs: https://github.com/SimpleWooden/ProxmoxVPNDeployment/blob/main/checklist/MANUAL-STEPS.md
EOF
