<#
.SYNOPSIS
  Create/update Dynamic DNS (os-ddclient / dyndns) account on OPNsense via API.
.NOTES
  Manual first: create the A record at your DNS host, install os-ddclient plugin,
  and put credentials in config.ps1. See checklist\MANUAL-STEPS.md.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\lib\OpnSenseApi.ps1"
$Config = Import-DeployConfig
$service = Resolve-DynDnsServiceName -Config $Config

Write-Host "==> Enabling DynDNS general settings"
$null = Invoke-OpnSenseApi -Config $Config -Method POST -Path 'api/dyndns/settings/set' -Body @{
    general = @{
        enabled      = '1'
        verbose      = '0'
        allowipv6    = '0'
        daemon_delay = [string]$Config.DynDnsInterval
        backend      = 'native'
    }
}

Write-Host "==> Searching existing DynDNS accounts for $($Config.VpnHostname)"
$search = Invoke-OpnSenseApi -Config $Config -Method GET `
    -Path ("api/dyndns/accounts/searchItem?current=1&rowCount=50&searchPhrase={0}" -f [uri]::EscapeDataString($Config.VpnHostname))

$accountBody = @{
    account = @{
        enabled          = '1'
        description      = "VPN $($Config.VpnHostname)"
        service          = $service
        username         = [string]$Config.DynDnsUsername
        password         = [string]$Config.DynDnsPassword
        zone             = [string]$Config.DnsZone
        hostnames        = [string]$Config.VpnHostname
        wildcard         = '0'
        checkip          = [string]$Config.DynDnsCheckIp
        interface        = [string]$Config.DynDnsInterface
        checkip_timeout  = '10'
        force_ssl        = '1'
    }
}

$uuid = $null
if ($search.rows -and $search.rows.Count -gt 0) {
    $uuid = $search.rows[0].uuid
    Write-Host "==> Updating existing account $uuid"
    $result = Invoke-OpnSenseApi -Config $Config -Method POST `
        -Path "api/dyndns/accounts/setItem/$uuid" -Body $accountBody
}
else {
    Write-Host "==> Creating DynDNS account ($service)"
    $result = Invoke-OpnSenseApi -Config $Config -Method POST `
        -Path 'api/dyndns/accounts/addItem' -Body $accountBody
    if ($result.uuid) { $uuid = $result.uuid }
}

Write-Host "==> Reconfigure DynDNS service"
$reconf = Invoke-OpnSenseApi -Config $Config -Method POST -Path 'api/dyndns/service/reconfigure'
$status = Invoke-OpnSenseApi -Config $Config -Method GET -Path 'api/dyndns/service/status'

$state = [pscustomobject]@{
    appliedAt   = (Get-Date).ToString('o')
    hostname    = $Config.VpnHostname
    zone        = $Config.DnsZone
    service     = $service
    accountUuid = $uuid
    reconfigure = $reconf
    status      = $status
    apiResult   = $result
}
$path = Write-StateJson -Name 'ddns.json' -Object $state
Write-Host "Saved $path"
Write-Host "Verify in UI: Services -> Dynamic DNS (Current IP should match WAN)."
Write-Host "Also: nslookup $($Config.VpnHostname)"
