# Manual steps (you must do these)

Scripts (Proxmox helper CT or Windows) automate keys, DynDNS, WireGuard peers/instance, and firewall automation rules. Everything below needs your DNS login, OPNsense UI, or a physical phone.

## Proxmox helper (recommended)

On the Proxmox host, create the minimal Alpine CT first (see README), then `pct enter <CTID>` and edit `/opt/opnsense-wg-helper/config.env` before running `opn-wg-configure`.

## Before any apply script

- [ ] **Backup** OPNsense: *System -> Configuration -> Backups -> Download*.
- [ ] Confirm WAN has a **public** IPv4 (*Interfaces -> Overview*). If it is `10.x`, `192.168.x`, or `100.64-100.127.x`, inbound WireGuard will fail (CGNAT).
- [ ] Install **os-ddclient** if needed: *System -> Firmware -> Plugins* -> `os-ddclient`.
- [ ] Create **API key**: *System -> Access -> Users* -> your user -> **API keys** -> add. Paste into `config.env`.
- [ ] Fill `config.env` (API keys, domain, DynDNS token) and adjust `peers.json` if needed.

## Phase 1 — DNS (DynDNS)

- [ ] At your DNS host, create **A record** `vpn` pointing at current public IP, TTL **60-300**.
- [ ] Create provider API credentials (Cloudflare: Zone -> DNS -> Edit on your zone).
- [ ] Put token in `config.env` (`DYNDNS_PASSWORD`; username `token` for Cloudflare).
- [ ] Run `opn-wg-configure` (or `helper/02-apply-ddns.sh`).
- [ ] UI check: *Services -> Dynamic DNS* shows **Current IP** matching WAN.
- [ ] `nslookup vpn.yourdomain.com` returns that IP.

## Phase 2 — WireGuard instance + interface

- [ ] Helper applies WireGuard instance/peers via API.
- [ ] UI: *VPN -> WireGuard -> Instances* shows **home**, port **51820**, peers listed.
- [ ] **Assign interface** (required):
  1. *Interfaces -> Assignments*
  2. Add WireGuard device (`wg0` / `wt0`)
  3. Enable interface (e.g. OPT1), Apply
- [ ] Then: `opn-wg-configure opt1`

## Phase 3 — Firewall

- [ ] WAN rule: UDP **51820** to This Firewall.
- [ ] WG interface: `10.10.10.0/24` -> LAN `192.168.0.0/22` (+ DNS optional).
- [ ] Do **not** expose WAN HTTPS/SSH management.

## Phase 4 — Client rollout

- [ ] Configs in helper CT: `/opt/opnsense-wg-helper/clients/*.conf`
- [ ] Install official WireGuard apps; import `.conf` or scan OPNsense QR.
- [ ] One peer per device; share securely (not long-lived plaintext email).

## Phase 5 — IP change test

- [ ] Phone on cellular: enable Home tunnel; ping `10.10.10.1` and `192.168.0.1`.
- [ ] Renew WAN / wait for DynDNS; confirm A record updates; reconnect via hostname.

## Destroy helper CT (optional)

VPN on OPNsense keeps working after:

```bash
pct stop <CTID> && pct destroy <CTID>
```
