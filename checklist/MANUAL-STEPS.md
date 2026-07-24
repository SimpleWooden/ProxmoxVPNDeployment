# Manual steps (you must do these)

Scripts automate keys, DynDNS account, WireGuard peers/instance, and firewall automation rules. Everything below needs your DNS login, OPNsense UI, or a physical phone.

## Before any apply script

- [ ] **Backup** OPNsense: *System → Configuration → Backups → Download*.
- [ ] Confirm WAN has a **public** IPv4 (*Interfaces → Overview*). If it is `10.x`, `192.168.x`, or `100.64–100.127.x`, inbound WireGuard will fail (CGNAT) — stop and reconsider Tailscale/Headscale.
- [ ] Install **os-ddclient** if needed: *System → Firmware → Plugins* → `os-ddclient`.
- [ ] Create **API key**: *System → Access → Users* → your user → **API keys** → add. Paste into `config.ps1`.
- [ ] Copy `config.example.ps1` → `config.ps1` and fill domain, DynDNS token, API key/secret.
- [ ] Copy `peers.example.json` → `peers.json` and adjust device names/IPs if needed.

## Phase 1 — DNS (DynDNS)

- [ ] At your DNS host, create **A record** `vpn` (or your chosen hostname) pointing at current public IP, TTL **60–300**.
- [ ] Create provider API credentials (Cloudflare recommended: Zone → DNS → Edit on your zone only).
- [ ] Put token in `config.ps1` (`DynDnsPassword`; username `token` for Cloudflare).
- [ ] Run `.\scripts\02-apply-ddns.ps1` (or `Deploy-All.ps1`).
- [ ] UI check: *Services → Dynamic DNS* shows **Current IP** matching WAN.
- [ ] PC check: `nslookup vpn.yourdomain.com` returns that IP.

## Phase 2 — WireGuard instance + interface

- [ ] Run `.\scripts\01-generate-peers.ps1` then `.\scripts\03-apply-wireguard.ps1`.
- [ ] UI: *VPN → WireGuard → Instances* shows **home** enabled, port **51820**, peers listed.
- [ ] **Assign interface** (required — not fully reliable via API):
  1. *Interfaces → Assignments*
  2. Add new assignment for the WireGuard device (`wg0` / `wt0` / similar)
  3. Enable the new interface (e.g. OPT1), description `WG_HOME`
  4. IPv4: typically leave as none if tunnel address is on the instance; follow your OPNsense version’s WireGuard guide if connectivity fails
  5. Apply changes
- [ ] Note the interface name (`opt1`, etc.) for the firewall script:  
  `.\scripts\04-apply-firewall.ps1 -WgInterface opt1`

## Phase 3 — Firewall

- [ ] Run `.\scripts\04-apply-firewall.ps1` (with `-WgInterface` if needed).
- [ ] Confirm *Firewall → Rules → WAN*: **Allow WireGuard WAN UDP** (UDP 51820 to This Firewall).
- [ ] Confirm rules on the WG interface: clients `10.10.10.0/24` → LAN `192.168.0.0/22` (+ DNS to firewall optional).
- [ ] Confirm **no** WAN allow for HTTPS 443 / SSH 22 to This Firewall for management.

## Phase 4 — Client rollout

- [ ] Run `.\scripts\05-export-clients.ps1`.
- [ ] Install official **WireGuard** apps on phones/PCs.
- [ ] Import each `clients\<name>.conf` (or scan QR from OPNsense peer UI / generated PNG).
- [ ] Share partner/friend configs in person or via a password manager — not long-lived plaintext email.
- [ ] Name tunnel **Home**; leave off on home Wi‑Fi if you like (split tunnel only hits LAN anyway).

## Phase 5 — “Always works when IP changes”

- [ ] Phone on **cellular** (Wi‑Fi off): activate Home tunnel.
- [ ] Ping `10.10.10.1` and `192.168.0.1` (or open a LAN service).
- [ ] Note WAN IP; *Interfaces → WAN → Renew* or wait for lease change; DynDNS should update within ~5 minutes.
- [ ] `nslookup` hostname → new IP; toggle tunnel off/on — still connects via hostname.
- [ ] Partner phone: open app → toggle Home only.

## If something fails

| Symptom | Likely cause |
| --- | --- |
| Handshake never completes | WAN not public / UDP 51820 blocked / wrong endpoint |
| Handshake OK, no LAN | WG interface not assigned / missing WG→LAN rule |
| DNS hostname wrong IP | DynDNS token/zone/hostname mismatch |
| API script `failed` | Plugin missing, wrong privilege on API key, or field rename on your OPNsense version — finish that piece in UI using the same values |

## Revoking a device

*VPN → WireGuard → Peers* → disable/delete that peer only → Apply. Delete their `.conf` from password managers.
