<#
.SYNOPSIS
  Create WireGuard server instance + peers on OPNsense from state\wireguard-keys.json.
.NOTES
  Run 01-generate-peers.ps1 first. After this script, complete interface assignment
  in the UI (checklist\MANUAL-STEPS.md Phase 2).
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\lib\OpnSenseApi.ps1"
$Config = Import-DeployConfig

$keys = Read-StateJson -Name 'wireguard-keys.json'
if (-not $keys) {
    throw "Missing state\wireguard-keys.json - run scripts\01-generate-peers.ps1 first."
}

# Ensure WireGuard enabled
Write-Host "==> Enabling WireGuard service"
$null = Invoke-OpnSenseApi -Config $Config -Method POST -Path 'api/wireguard/general/set' -Body @{
    general = @{ enabled = '1' }
}

# Create peers (clients) first
$peerUuids = @()
$peerMap = @()
foreach ($peer in $keys.peers) {
    Write-Host "==> Ensuring peer $($peer.name)"
    $search = Invoke-OpnSenseApi -Config $Config -Method GET `
        -Path ("api/wireguard/client/searchClient?current=1&rowCount=50&searchPhrase={0}" -f [uri]::EscapeDataString($peer.name))

    $clientBody = @{
        client = @{
            enabled             = '1'
            name                = [string]$peer.name
            pubkey              = [string]$peer.publicKey
            psk                 = ''
            tunneladdress       = [string]$peer.tunnelAddress
            serveraddress       = ''
            serverport          = ''
            keepalive           = [string]$peer.keepalive
            endpoint            = ''
            endpointport        = ''
            servers             = ''
        }
    }

    # Field name varies by version: persistentkeepalive vs keepalive
    $clientBody.client.persistentkeepalive = [string]$peer.keepalive

    $uuid = $null
    if ($search.rows -and $search.rows.Count -gt 0) {
        $uuid = $search.rows[0].uuid
        Write-Host "    Updating $uuid"
        $null = Invoke-OpnSenseApi -Config $Config -Method POST `
            -Path "api/wireguard/client/setClient/$uuid" -Body $clientBody
    }
    else {
        Write-Host "    Creating"
        $created = Invoke-OpnSenseApi -Config $Config -Method POST `
            -Path 'api/wireguard/client/addClient' -Body $clientBody
        if ($created.result -eq 'failed') {
            throw "addClient failed for $($peer.name): $($created | ConvertTo-Json -Compress)"
        }
        $uuid = $created.uuid
    }
    if (-not $uuid) { throw "No UUID for peer $($peer.name)" }
    $peerUuids += $uuid
    $peerMap += [pscustomobject]@{ name = $peer.name; uuid = $uuid; tunnelAddress = $peer.tunnelAddress }
}

# Create / update server instance
Write-Host "==> Ensuring WireGuard instance $($keys.instanceName)"
$srvSearch = Invoke-OpnSenseApi -Config $Config -Method GET `
    -Path ("api/wireguard/server/searchServer?current=1&rowCount=50&searchPhrase={0}" -f [uri]::EscapeDataString($keys.instanceName))

$peersCsv = ($peerUuids -join ',')
$serverBody = @{
    server = @{
        enabled      = '1'
        name         = [string]$keys.instanceName
        pubkey       = [string]$keys.serverPublicKey
        privkey      = [string]$keys.serverPrivateKey
        tunneladdress = [string]$keys.tunnelServer
        port         = [string]$keys.listenPort
        peers        = $peersCsv
        dns          = [string]$Config.WgDns
        mtu          = ''
        disableroutes = '0'
        gateway      = ''
        carp_depend_on = ''
    }
}

$serverUuid = $null
if ($srvSearch.rows -and $srvSearch.rows.Count -gt 0) {
    $serverUuid = $srvSearch.rows[0].uuid
    Write-Host "    Updating server $serverUuid"
    $set = Invoke-OpnSenseApi -Config $Config -Method POST `
        -Path "api/wireguard/server/setServer/$serverUuid" -Body $serverBody
    if ($set.result -eq 'failed') {
        throw "setServer failed: $($set | ConvertTo-Json -Depth 6 -Compress)"
    }
}
else {
    Write-Host "    Creating server"
    $created = Invoke-OpnSenseApi -Config $Config -Method POST `
        -Path 'api/wireguard/server/addServer' -Body $serverBody
    if ($created.result -eq 'failed') {
        throw "addServer failed: $($created | ConvertTo-Json -Depth 6 -Compress)"
    }
    $serverUuid = $created.uuid
}

Write-Host "==> Reconfigure WireGuard"
$reconf = Invoke-OpnSenseApi -Config $Config -Method POST -Path 'api/wireguard/service/reconfigure'

$state = [pscustomobject]@{
    appliedAt   = (Get-Date).ToString('o')
    serverUuid  = $serverUuid
    peerUuids   = $peerMap
    reconfigure = $reconf
}
$path = Write-StateJson -Name 'wireguard-applied.json' -Object $state
Write-Host "Saved $path"
Write-Host ""
Write-Host "MANUAL (required): Interfaces -> Assignments -> add WireGuard device (wt0/wg0),"
Write-Host "  enable interface, then apply. See checklist\MANUAL-STEPS.md"
Write-Host "Then run scripts\04-apply-firewall.ps1"
