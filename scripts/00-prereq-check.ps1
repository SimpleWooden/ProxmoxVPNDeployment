<#
.SYNOPSIS
  Install local tooling for the OPNsense WireGuard deploy kit.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
$VenvPython = Join-Path $Root '.venv\Scripts\python.exe'
$Req = Join-Path $Root 'requirements.txt'

Write-Host "==> Checking Python"
$py = Get-Command python -ErrorAction SilentlyContinue
if (-not $py) { throw "Python not found on PATH. Install Python 3.11+ and re-run." }

if (-not (Test-Path $VenvPython)) {
    Write-Host "==> Creating .venv"
    & python -m venv (Join-Path $Root '.venv')
}

Write-Host "==> Installing Python deps"
& $VenvPython -m pip install --upgrade pip | Out-Null
& $VenvPython -m pip install -r $Req

Write-Host "==> Verifying WireGuard keygen"
$keysPy = Join-Path $PSScriptRoot 'lib\wgkeys.py'
$sample = & $VenvPython $keysPy | ConvertFrom-Json
if (-not $sample.publicKey) { throw "Keygen failed" }
Write-Host "    OK ($($sample.publicKey.Substring(0,8))...)"

Write-Host "==> Checking config files"
$config = Join-Path $Root 'config.ps1'
$peers = Join-Path $Root 'peers.json'
if (-not (Test-Path $config)) {
    Copy-Item (Join-Path $Root 'config.example.ps1') $config
    Write-Host "    Created config.ps1 from example - EDIT IT before applying."
}
else {
    Write-Host "    config.ps1 present"
}
if (-not (Test-Path $peers)) {
    Copy-Item (Join-Path $Root 'peers.example.json') $peers
    Write-Host "    Created peers.json from example - EDIT device list if needed."
}
else {
    Write-Host "    peers.json present"
}

Write-Host ""
Write-Host "Prereqs ready. Next:"
Write-Host "  1. Edit config.ps1 (API keys, domain, DynDNS token)"
Write-Host "  2. Edit peers.json (devices)"
Write-Host "  3. Complete checklist\MANUAL-STEPS.md DNS A-record + API key creation"
Write-Host "  4. Run .\scripts\Deploy-All.ps1  (or step scripts 01-06)"
