<#
.SYNOPSIS
  Regenerate client .conf files from state\wireguard-keys.json and print rollout tips.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\lib\OpnSenseApi.ps1"

$Root = Get-RepoRoot
$ConfigPath = Join-Path $Root 'config.ps1'
$Config = if (Test-Path $ConfigPath) { & $ConfigPath } else { & (Join-Path $Root 'config.example.ps1') }

$keys = Read-StateJson -Name 'wireguard-keys.json'
if (-not $keys) { throw "Run scripts\01-generate-peers.ps1 first." }

$ClientsDir = Join-Path $Root 'clients'
if (-not (Test-Path $ClientsDir)) { New-Item -ItemType Directory -Path $ClientsDir | Out-Null }

$readme = Join-Path $ClientsDir 'ROLLOUT.txt'
$lines = @(
    'WireGuard client rollout',
    '========================',
    '',
    '1. Install official WireGuard app (phone or PC).',
    '2. Phones: open the matching .conf QR (see below) or AirDrop/secure share the .conf.',
    '3. PCs: WireGuard -> Import tunnel(s) from file -> select the .conf -> Activate.',
    '4. Name the tunnel "Home". Toggle on when away from the house.',
    '5. Test from cellular data (Wi-Fi off): ping 10.10.10.1 and 192.168.0.1',
    '',
    "Endpoint: $($keys.vpnHostname):$($keys.listenPort)",
    "LAN routes: $($keys.lanCidr)",
    '',
    'Configs:'
)

foreach ($peer in $keys.peers) {
    $dnsLine = ''
    if ($Config.WgDns) { $dnsLine = "DNS = $($Config.WgDns)" }
    $conf = @"
[Interface]
PrivateKey = $($peer.privateKey)
Address = $($peer.tunnelAddress)
$dnsLine

[Peer]
PublicKey = $($keys.serverPublicKey)
Endpoint = $($keys.vpnHostname):$($keys.listenPort)
AllowedIPs = $($keys.lanCidr)
PersistentKeepalive = $($peer.keepalive)
"@
    $conf = ($conf -split "`n" | Where-Object { $_.Trim() -ne '' }) -join "`r`n"
    $confPath = Join-Path $ClientsDir "$($peer.name).conf"
    Set-Content -Path $confPath -Value $conf -Encoding UTF8
    $lines += "  - $($peer.name): $confPath"
}

$qrencode = Get-Command qrencode -ErrorAction SilentlyContinue
if ($qrencode) {
    foreach ($peer in $keys.peers) {
        if ($peer.platform -ne 'mobile') { continue }
        $confPath = Join-Path $ClientsDir "$($peer.name).conf"
        $png = Join-Path $ClientsDir "$($peer.name).png"
        & qrencode -t PNG -o $png -r $confPath
        $lines += "  QR: $png"
    }
}
else {
    $lines += ''
    $lines += 'Tip: OPNsense UI also shows a QR per peer (VPN -> WireGuard -> Peers).'
    $lines += 'Or install qrencode later to auto-build PNGs here.'
}

$lines += ''
$lines += 'Security: one peer per device. If a phone is lost, disable that peer only.'
Set-Content -Path $readme -Value ($lines -join "`r`n") -Encoding UTF8

Write-Host ($lines -join "`n")
Write-Host ""
Write-Host "Wrote $readme"
