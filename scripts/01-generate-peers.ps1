<#
.SYNOPSIS
  Generate WireGuard keys and client .conf files locally (no router access required).
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\lib\OpnSenseApi.ps1"

$Root = Get-RepoRoot
$ConfigPath = Join-Path $Root 'config.ps1'
if (-not (Test-Path $ConfigPath)) {
    Copy-Item (Join-Path $Root 'config.example.ps1') $ConfigPath
    Write-Warning "Created config.ps1 from example. Using example hostname until you edit it."
}
$Config = & $ConfigPath
if ($Config -isnot [hashtable] -and $Config -isnot [System.Collections.IDictionary]) {
    throw "config.ps1 must return a hashtable"
}

$PeersPath = Join-Path $Root ([string]$Config.PeersFile)
if (-not (Test-Path $PeersPath)) {
    $PeersPath = Join-Path $Root 'peers.example.json'
}
$Peers = Get-Content -Raw $PeersPath | ConvertFrom-Json
if (-not $Peers -or $Peers.Count -lt 1) { throw "No peers defined in $PeersPath" }

$ClientsDir = Join-Path $Root 'clients'
if (-not (Test-Path $ClientsDir)) { New-Item -ItemType Directory -Path $ClientsDir | Out-Null }

Write-Host "==> Generating server keypair"
$server = New-WgKeyPair

$peerState = @()
$index = 0
foreach ($peer in $Peers) {
    $index++
    Write-Host "==> Peer $($peer.name) ($($peer.tunnelAddress))"
    $kp = New-WgKeyPair
    $keepalive = if ($peer.keepalive) { [int]$peer.keepalive } else { 25 }
    $dnsLine = ''
    if (-not [string]::IsNullOrWhiteSpace([string]$Config.WgDns)) {
        $dnsLine = "DNS = $($Config.WgDns)"
    }

    $conf = @"
[Interface]
PrivateKey = $($kp.privateKey)
Address = $($peer.tunnelAddress)
$dnsLine

[Peer]
PublicKey = $($server.publicKey)
Endpoint = $($Config.VpnHostname):$($Config.WgListenPort)
AllowedIPs = $($Config.WgLanCidr)
PersistentKeepalive = $keepalive
"@
    # tidy blank DNS line if empty
    $conf = ($conf -split "`n" | Where-Object { $_.Trim() -ne '' }) -join "`r`n"
    $confPath = Join-Path $ClientsDir "$($peer.name).conf"
    Set-Content -Path $confPath -Value $conf -Encoding UTF8

    $peerState += [pscustomobject]@{
        name           = $peer.name
        tunnelAddress  = $peer.tunnelAddress
        keepalive      = $keepalive
        platform       = $peer.platform
        publicKey      = $kp.publicKey
        privateKey     = $kp.privateKey
        confPath       = $confPath
    }
}

$state = [pscustomobject]@{
    generatedAt    = (Get-Date).ToString('o')
    vpnHostname    = $Config.VpnHostname
    listenPort     = $Config.WgListenPort
    lanCidr        = $Config.WgLanCidr
    tunnelServer   = $Config.WgTunnelCidr
    instanceName   = $Config.WgInstanceName
    serverPublicKey  = $server.publicKey
    serverPrivateKey = $server.privateKey
    peers          = $peerState
}

$statePath = Write-StateJson -Name 'wireguard-keys.json' -Object $state
Write-Host ""
Write-Host "Wrote server + peer keys to $statePath"
Write-Host "Client configs in $ClientsDir"
Write-Host "IMPORTANT: Keep state\wireguard-keys.json private (contains private keys)."
Write-Host "Next: complete DNS manual steps, then run 02-apply-ddns.ps1 / 03-apply-wireguard.ps1"
