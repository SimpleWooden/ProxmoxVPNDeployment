#!/usr/bin/env bash
# Create a minimal Alpine LXC on Proxmox that hosts the OPNsense WireGuard
# + DynDNS configuration helper (does NOT terminate VPN itself).
#
# Run as root on the Proxmox VE host:
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/OWNER/REPO/main/proxmox/create-helper-ct.sh)"
#
# Or:
#   git clone ... && cd ... && bash proxmox/create-helper-ct.sh
#
# Minimum defaults: 1 vCPU, 128 MB RAM, 1 GB disk, Alpine, unprivileged.

set -euo pipefail

# --------------- defaults (override via env) ---------------
CTID="${CTID:-}"
CT_HOSTNAME="${CT_HOSTNAME:-opn-wg-helper}"
STORAGE="${STORAGE:-}"
BRIDGE="${BRIDGE:-vmbr0}"
IPCONFIG="${IPCONFIG:-ip=dhcp}"
CORES="${CORES:-1}"
MEMORY_MB="${MEMORY_MB:-128}"
SWAP_MB="${SWAP_MB:-128}"
DISK_GB="${DISK_GB:-1}"
TEMPLATE_STORAGE="${TEMPLATE_STORAGE:-local}"
ALPINE_VERSION="${ALPINE_VERSION:-3.21}"
REPO_URL="${REPO_URL:-}"
REPO_REF="${REPO_REF:-main}"
START_CT="${START_CT:-1}"
UNPRIVILEGED="${UNPRIVILEGED:-1}"
PASSWORD="${PASSWORD:-}"   # root password inside CT; random if empty
HELPER_DIR="/opt/opnsense-wg-helper"

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "==> $*"; }
need() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1 (run on Proxmox host)"; }

[[ "$(id -u)" -eq 0 ]] || die "Run as root on the Proxmox host"
need pct
need pvesm
need wget

# Resolve next free CTID
if [[ -z "$CTID" ]]; then
  CTID=200
  while pct status "$CTID" &>/dev/null; do CTID=$((CTID + 1)); done
fi
pct status "$CTID" &>/dev/null && die "CTID $CTID already exists"

# Pick storage with enough free space if not set
if [[ -z "$STORAGE" ]]; then
  STORAGE="$(pvesm status -content rootdir | awk 'NR>1 && $2!="dir" {print $1; exit}')"
  [[ -n "$STORAGE" ]] || STORAGE="$(pvesm status -content rootdir | awk 'NR>1 {print $1; exit}')"
  [[ -n "$STORAGE" ]] || die "No storage with rootdir content found. Set STORAGE=..."
fi

if [[ -z "$PASSWORD" ]]; then
  PASSWORD="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20)"
  GENERATED_PW=1
else
  GENERATED_PW=0
fi

# Ensure Alpine template
info "Ensuring Alpine ${ALPINE_VERSION} LXC template on ${TEMPLATE_STORAGE}"
pveam update >/dev/null || true
TEMPLATE="$(pveam available -section system | awk -v v="$ALPINE_VERSION" '$2 ~ ("alpine-" v) && $2 ~ /default/ {print $2; exit}')"
[[ -n "$TEMPLATE" ]] || TEMPLATE="$(pveam available -section system | awk '/alpine-.*-default/ {print $2; exit}')"
[[ -n "$TEMPLATE" ]] || die "No Alpine template found via pveam. Download one manually."

if ! pveam list "$TEMPLATE_STORAGE" | awk '{print $1}' | grep -qx "$TEMPLATE"; then
  info "Downloading $TEMPLATE"
  pveam download "$TEMPLATE_STORAGE" "$TEMPLATE"
fi
TEMPLATE_PATH="${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}"

info "Creating CT ${CTID} (${CT_HOSTNAME}) - ${CORES} CPU, ${MEMORY_MB}M RAM, ${DISK_GB}G disk"
pct create "$CTID" "$TEMPLATE_PATH" \
  --hostname "$CT_HOSTNAME" \
  --cores "$CORES" \
  --memory "$MEMORY_MB" \
  --swap "$SWAP_MB" \
  --rootfs "${STORAGE}:${DISK_GB}" \
  --net0 "name=eth0,bridge=${BRIDGE},${IPCONFIG}" \
  --unprivileged "$UNPRIVILEGED" \
  --features nesting=0 \
  --onboot 0 \
  --password "$PASSWORD" \
  --start 0

# Tiny Alpine: enable community repo + packages inside CT after start
pct start "$CTID"
sleep 3

info "Installing packages inside CT (curl jq wireguard-tools-wg bash git)"
pct exec "$CTID" -- sh -c '
  set -e
  if [ -f /etc/apk/repositories ]; then
    sed -i "s/^#\s*\(.*\/community\)/\1/" /etc/apk/repositories || true
    apk update
    apk add --no-cache bash curl jq wireguard-tools-wg git ca-certificates bind-tools
  elif command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq bash curl jq wireguard-tools git ca-certificates dnsutils
  else
    echo "Unsupported CT OS"; exit 1
  fi
'

# Install helper tree into CT
TMP_CLONE="$(mktemp -d)"
cleanup() { rm -rf "$TMP_CLONE"; }
trap cleanup EXIT

if [[ -n "$REPO_URL" ]]; then
  info "Cloning $REPO_URL ($REPO_REF)"
  git clone --depth 1 --branch "$REPO_REF" "$REPO_URL" "$TMP_CLONE/repo"
elif [[ -f "$(dirname "$0")/../helper/configure.sh" ]]; then
  info "Copying local repository into CT"
  mkdir -p "$TMP_CLONE/repo"
  # copy from script location when run from a checkout
  ROOT="$(cd "$(dirname "$0")/.." && pwd)"
  # Prefer rsync if available
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --exclude '.venv' --exclude 'state' --exclude 'clients' --exclude '.git' \
      --exclude 'config.env' --exclude 'config.ps1' "$ROOT/" "$TMP_CLONE/repo/"
  else
    tar -C "$ROOT" --exclude=.venv --exclude=state --exclude=clients --exclude=.git \
      --exclude=config.env --exclude=config.ps1 -cf - . | tar -C "$TMP_CLONE/repo" -xf -
  fi
else
  die "Set REPO_URL=https://github.com/OWNER/REPO.git or run from a git checkout"
fi

pct exec "$CTID" -- mkdir -p "$HELPER_DIR"
tar -C "$TMP_CLONE/repo" -cf - . | pct exec "$CTID" -- tar -C "$HELPER_DIR" -xf -
pct exec "$CTID" -- sh -c "chmod +x ${HELPER_DIR}/helper/*.sh ${HELPER_DIR}/proxmox/*.sh 2>/dev/null || true"
pct exec "$CTID" -- sh -c "
  cd ${HELPER_DIR}
  cp -n config.example.env config.env || true
  cp -n peers.example.json peers.json || true
"

# Convenience wrapper
pct exec "$CTID" -- sh -c "cat > /usr/local/bin/opn-wg-configure <<'EOF'
#!/bin/sh
cd ${HELPER_DIR} && exec bash helper/configure.sh \"\$@\"
EOF
chmod +x /usr/local/bin/opn-wg-configure"

CT_IP="$(pct exec "$CTID" -- sh -c "ip -4 -o addr show eth0 2>/dev/null | awk '{print \$4}' | cut -d/ -f1 | head -n1" || true)"

cat <<EOF

============================================================
Proxmox helper CT ready (minimal footprint)
============================================================
  CTID:       ${CTID}
  Hostname:   ${CT_HOSTNAME}
  Resources:  ${CORES} vCPU / ${MEMORY_MB} MB RAM / ${DISK_GB} GB disk
  Bridge:     ${BRIDGE}
  IP:         ${CT_IP:-dhcp-pending}
  Path:       ${HELPER_DIR}
$([ "$GENERATED_PW" -eq 1 ] && echo "  root pass:  ${PASSWORD}" || echo "  root pass:  (as provided)")

Next steps:
  1) Enter the CT:
       pct enter ${CTID}

  2) Edit settings:
       nano ${HELPER_DIR}/config.env
       nano ${HELPER_DIR}/peers.json

  3) On OPNsense (manual once):
       - Backup config
       - Install os-ddclient plugin if needed
       - Create API key (System -> Access -> Users)
       - Create DNS A record for VPN_HOSTNAME

  4) Configure OPNsense WireGuard + DynDNS from inside the CT:
       opn-wg-configure
     # or: bash ${HELPER_DIR}/helper/configure.sh
     # after assigning WG interface, pass it: opn-wg-configure opt1

  5) Import clients/*.conf into WireGuard apps; test on cellular.

Notes:
  - VPN terminates on OPNsense (not in this CT).
  - This CT only runs the configuration helper (tiny Alpine LXC).
  - Destroy later: pct stop ${CTID} && pct destroy ${CTID}
============================================================
EOF

if [[ "$START_CT" != "1" ]]; then
  pct stop "$CTID" || true
fi
