<#
.SYNOPSIS
  Run automated deploy steps in order. Pauses for required manual UI actions.
#>
param(
    [switch]$SkipDdns,
    [switch]$SkipFirewall,
    [string]$WgInterface = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$here = $PSScriptRoot
Write-Host "=== OPNsense WireGuard + DynDNS deploy ===" -ForegroundColor Cyan

& "$here\00-prereq-check.ps1"
Write-Host ""
Write-Host "Press Enter after you have edited config.ps1 and peers.json, created the DNS A record,"
Write-Host "installed os-ddclient (if needed), and created an OPNsense API key with privileges."
Pause

& "$here\01-generate-peers.ps1"
Write-Host ""

if (-not $SkipDdns) {
    & "$here\02-apply-ddns.ps1"
    Write-Host ""
}

& "$here\03-apply-wireguard.ps1"
Write-Host ""
Write-Host "MANUAL REQUIRED: Assign & enable the WireGuard interface in OPNsense UI."
Write-Host "See checklist\MANUAL-STEPS.md Phase 2 (interface assignment)."
Write-Host "Press Enter when the WG interface is assigned and enabled."
Pause

if (-not $SkipFirewall) {
    if ($WgInterface) {
        & "$here\04-apply-firewall.ps1" -WgInterface $WgInterface
    }
    else {
        & "$here\04-apply-firewall.ps1"
    }
    Write-Host ""
}

& "$here\05-export-clients.ps1"
Write-Host ""
& "$here\06-verify.ps1" -CheckApi
Write-Host ""
Write-Host "=== Automated portion complete ===" -ForegroundColor Green
Write-Host "Finish client installs + cellular / IP-change tests in checklist\MANUAL-STEPS.md"
