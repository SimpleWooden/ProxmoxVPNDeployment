# OPNsense WireGuard + DynDNS — Proxmox helper

Minimal **Alpine LXC** on Proxmox that configures free WireGuard VPN + Dynamic DNS on your OPNsense firewall via API.

The VPN **terminates on OPNsense** (your Sophos XG hardware). The container only hosts the automation helper — about **1 vCPU / 128 MB RAM / 1 GB disk**.

## One-liner (on Proxmox host as root)

Creates an interactive wizard. Defaults: hostname **BTAL01**, IP **192.168.0.122/22**, gateway/DNS **192.168.0.1**.

**Do not** use `bash -c "$(curl ...)"` — that breaks the script. Use process substitution:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/SimpleWooden/ProxmoxVPNDeployment/main/proxmox/create-helper-ct.sh)
```

Or download then run:

```bash
curl -fsSL https://raw.githubusercontent.com/SimpleWooden/ProxmoxVPNDeployment/main/proxmox/create-helper-ct.sh -o /tmp/create-helper-ct.sh
bash /tmp/create-helper-ct.sh
```

## After the CT is created

```bash
pct enter <CTID>
nano /opt/opnsense-wg-helper/config.env    # API keys, domain, DynDNS token
nano /opt/opnsense-wg-helper/peers.json    # devices
# On OPNsense: backup, os-ddclient, API key, DNS A record (see checklist/MANUAL-STEPS.md)
opn-wg-configure
# After assigning WireGuard interface in OPNsense UI:
opn-wg-configure opt1
```

## Required settings (`config.env`)

| Variable | Example | Meaning |
| --- | --- | --- |
| `OPNSENSE_URL` | `https://192.168.0.1` | OPNsense LAN URL |
| `OPNSENSE_API_KEY` / `OPNSENSE_API_SECRET` | from OPNsense user API keys | API auth |
| `VPN_HOSTNAME` | `vpn.example.com` | Sticky hostname for clients |
| `DNS_ZONE` | `example.com` | DNS zone (Cloudflare Zone name) |
| `DYNDNS_PROVIDER` | `cloudflare` | or set `DYNDNS_SERVICE` to exact OPNsense label |
| `DYNDNS_USERNAME` | `token` | Cloudflare API token auth |
| `DYNDNS_PASSWORD` | API token | DynDNS secret |
| `WG_LAN_CIDR` | `192.168.0.0/22` | What clients can reach |
| `WG_TUNNEL_CIDR` | `10.10.10.1/24` | WireGuard tunnel |
| `WG_LISTEN_PORT` | `51820` | UDP port on WAN |

## Layout

| Path | Role |
| --- | --- |
| [proxmox/create-helper-ct.sh](proxmox/create-helper-ct.sh) | Run on Proxmox — creates Alpine LXC |
| [helper/](helper/) | Bash apply scripts (keys, DynDNS, WireGuard, firewall) |
| [checklist/MANUAL-STEPS.md](checklist/MANUAL-STEPS.md) | DNS / UI / phone steps only you can do |
| [config.example.env](config.example.env) | Settings template |
| [peers.example.json](peers.example.json) | Device list template |
| [scripts/](scripts/) | Optional Windows PowerShell variants |

## Security

- Never commit `config.env`, `state/`, or `clients/*.conf`.
- One WireGuard peer per device; revoke lost phones by disabling that peer.
- Do not expose OPNsense HTTPS/SSH on WAN.

## Destroy the helper CT

```bash
pct stop <CTID> && pct destroy <CTID>
```

WireGuard on OPNsense keeps working after the helper CT is removed.
