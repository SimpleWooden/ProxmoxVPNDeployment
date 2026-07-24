# OPNsense WireGuard + Dynamic DNS — Deploy Kit

Prefer the **Proxmox Alpine helper CT** (minimal resources). See **[README.md](README.md)**.

Windows PowerShell scripts under `scripts/` remain available if you configure from a PC instead of Proxmox.

## Proxmox (recommended)

On the Proxmox host as root (set your GitHub URL):

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/SimpleWooden/ProxmoxVPNDeployment/main/proxmox/create-helper-ct.sh)"
```

Default CT: hostname **BTAL01**, IP **192.168.0.122/22**, gateway/DNS **192.168.0.1**.

Then `pct enter <CTID>`, edit `config.env`, run `opn-wg-configure`.

## Manual checklist

See [checklist/MANUAL-STEPS.md](checklist/MANUAL-STEPS.md) for DNS A-record, API key, WireGuard interface assignment, and phone tests.
