# OPNsense WireGuard + Dynamic DNS — Deploy Kit

Prefer the **Proxmox Alpine helper CT** (minimal resources). See **[README.md](README.md)**.

Windows PowerShell scripts under `scripts/` remain available if you configure from a PC instead of Proxmox.

## Proxmox (recommended)

On the Proxmox host as root (set your GitHub URL):

```bash
export REPO_URL="https://github.com/OWNER/REPO.git"
bash -c "$(curl -fsSL https://raw.githubusercontent.com/OWNER/REPO/main/proxmox/create-helper-ct.sh)"
```

Then `pct enter <CTID>`, edit `config.env`, run `opn-wg-configure`.

## Manual checklist

See [checklist/MANUAL-STEPS.md](checklist/MANUAL-STEPS.md) for DNS A-record, API key, WireGuard interface assignment, and phone tests.
