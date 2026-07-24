<#
.SYNOPSIS
  Local verification helpers: DNS resolution, optional API status, connectivity tips.
#>
param(
    [switch]$CheckApi,
    [switch]$ForceDnsLookup
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\lib\OpnSenseApi.ps1"

$Root = Get-RepoRoot
$ConfigPath = Join-Path $Root 'config.ps1'
if (-not (Test-Path $ConfigPath)) {
    throw "Missing config.ps1"
}
$Config = Import-DeployConfig

Write-Host "==> DNS lookup for $($Config.VpnHostname)"
try {
    $records = Resolve-DnsName -Name $Config.VpnHostname -Type A -ErrorAction Stop
    foreach ($r in $records) {
        if ($r.IPAddress) { Write-Host "    A $($r.IPAddress) (TTL $($r.TTL))" }
    }
}
catch {
    Write-Warning "DNS lookup failed: $($_.Exception.Message)"
    Write-Warning "Create/fix the A record and wait for TTL, or check DynDNS."
}

if ($CheckApi) {
    Write-Host "==> OPNsense API reachability"
    try {
        $fw = Invoke-OpnSenseApi -Config $Config -Method GET -Path 'api/dyndns/service/status'
        Write-Host "    DynDNS status: $($fw | ConvertTo-Json -Compress)"
    }
    catch { Write-Warning "DynDNS status: $($_.Exception.Message)" }

    try {
        $wg = Invoke-OpnSenseApi -Config $Config -Method GET -Path 'api/wireguard/service/show'
        Write-Host "    WireGuard show: OK (see UI Diagnostics for handshake details)"
        Write-StateJson -Name 'wg-show.json' -Object $wg | Out-Null
    }
    catch {
        # older/newer endpoint names
        try {
            $wg = Invoke-OpnSenseApi -Config $Config -Method GET -Path 'api/wireguard/service/status'
            Write-Host "    WireGuard status: $($wg | ConvertTo-Json -Compress)"
        }
        catch { Write-Warning "WireGuard status: $($_.Exception.Message)" }
    }

    $ddns = Read-StateJson -Name 'ddns.json'
    $fwState = Read-StateJson -Name 'firewall.json'
    $wgApp = Read-StateJson -Name 'wireguard-applied.json'
    Write-Host "==> Local state files"
    Write-Host "    ddns: $(if ($ddns) { 'present' } else { 'missing - run 02' })"
    Write-Host "    wireguard-applied: $(if ($wgApp) { 'present' } else { 'missing - run 03' })"
    Write-Host "    firewall: $(if ($fwState) { 'present' } else { 'missing - run 04' })"
}

Write-Host ""
Write-Host "==> Manual IP-change test (you run this)"
Write-Host "  1. Note WAN IP in OPNsense Interfaces -> Overview"
Write-Host "  2. Connect a phone on cellular with WireGuard Home tunnel ON"
Write-Host "  3. Ping 10.10.10.1 and a LAN host (e.g. 192.168.0.1)"
Write-Host "  4. Renew WAN DHCP or force DynDNS update; confirm DNS A record changes"
Write-Host "  5. Toggle tunnel off/on - should reconnect via $($Config.VpnHostname)"
Write-Host ""
Write-Host "Checklist file: checklist\MANUAL-STEPS.md (Phase 5)"
