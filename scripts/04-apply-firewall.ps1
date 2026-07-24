<#
.SYNOPSIS
  Add WAN WireGuard allow + WG-net -> LAN allow rules via Firewall Automation API.
.NOTES
  After assigning the WireGuard interface in the UI, note its name (often "opt1"
  or "wg0"). Set -WgInterface if auto-detect fails.
#>
param(
    [string]$WgInterface = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\lib\OpnSenseApi.ps1"
$Config = Import-DeployConfig

function Get-WgInterfaceHint {
    param($Config, [string]$Override)
    if ($Override) { return $Override }
    try {
        $list = Invoke-OpnSenseApi -Config $Config -Method GET -Path 'api/firewall/filter/getInterfaceList'
        # Response shape varies; search for wireguard-ish keys
        $json = $list | ConvertTo-Json -Depth 8
        if ($json -match '"((?:opt\d+|wg\d+|wireguard[^"]*))"') {
            return $Matches[1]
        }
    }
    catch {
        Write-Warning "Could not auto-detect WG interface: $($_.Exception.Message)"
    }
    return ''
}

$wgIf = Get-WgInterfaceHint -Config $Config -Override $WgInterface
if (-not $wgIf) {
    Write-Warning "WireGuard interface not detected. WAN rule will still be created."
    Write-Warning "Re-run with -WgInterface opt1 (or your assigned name) after Interfaces -> Assignments."
}

$tunnelNet = ($Config.WgTunnelCidr -replace '/\d+$', '/24')
if ($Config.WgTunnelCidr -match '^(\d+\.\d+\.\d+)\.\d+/(\d+)$') {
    $tunnelNet = "$($Matches[1]).0/24"
}

function Ensure-Rule {
    param(
        [hashtable]$Config,
        [string]$Description,
        [hashtable]$RuleFields
    )
    $search = Invoke-OpnSenseApi -Config $Config -Method GET `
        -Path ("api/firewall/filter/searchRule?current=1&rowCount=20&searchPhrase={0}" -f [uri]::EscapeDataString($Description))
    if ($search.rows -and $search.rows.Count -gt 0) {
        $uuid = $search.rows[0].uuid
        Write-Host "==> Updating rule '$Description' ($uuid)"
        $body = @{ rule = $RuleFields }
        $null = Invoke-OpnSenseApi -Config $Config -Method POST `
            -Path "api/firewall/filter/setRule/$uuid" -Body $body
        return $uuid
    }
    Write-Host "==> Creating rule '$Description'"
    $body = @{ rule = $RuleFields }
    $created = Invoke-OpnSenseApi -Config $Config -Method POST `
        -Path 'api/firewall/filter/addRule' -Body $body
    if (-not $created.uuid) {
        throw "addRule failed for $Description : $($created | ConvertTo-Json -Compress)"
    }
    return $created.uuid
}

# WAN: allow UDP 51820 to This Firewall
$wanUuid = Ensure-Rule -Config $Config -Description 'Allow WireGuard WAN UDP' -RuleFields @{
    enabled            = '1'
    sequence           = '1'
    action             = 'pass'
    quick              = '1'
    interface          = 'wan'
    direction          = 'in'
    ipprotocol         = 'inet'
    protocol           = 'UDP'
    source_net         = 'any'
    source_not         = '0'
    source_port        = ''
    destination_net    = '(self)'
    destination_not    = '0'
    destination_port   = [string]$Config.WgListenPort
    log                = '1'
    description        = 'Allow WireGuard WAN UDP'
}

$wgUuid = $null
if ($wgIf) {
    $wgUuid = Ensure-Rule -Config $Config -Description 'Allow WireGuard clients to LAN' -RuleFields @{
        enabled            = '1'
        sequence           = '1'
        action             = 'pass'
        quick              = '1'
        interface          = $wgIf
        direction          = 'in'
        ipprotocol         = 'inet'
        protocol           = 'any'
        source_net         = $tunnelNet
        source_not         = '0'
        destination_net    = [string]$Config.WgLanCidr
        destination_not    = '0'
        log                = '0'
        description        = 'Allow WireGuard clients to LAN'
    }

    $null = Ensure-Rule -Config $Config -Description 'Allow WireGuard clients to DNS' -RuleFields @{
        enabled            = '1'
        sequence           = '1'
        action             = 'pass'
        quick              = '1'
        interface          = $wgIf
        direction          = 'in'
        ipprotocol         = 'inet'
        protocol           = 'UDP'
        source_net         = $tunnelNet
        destination_net    = '(self)'
        destination_port   = '53'
        log                = '0'
        description        = 'Allow WireGuard clients to DNS'
    }
}

Write-Host "==> Applying firewall rules (60s auto-rollback unless cancelled)"
$sp = Invoke-OpnSenseApi -Config $Config -Method POST -Path 'api/firewall/filter/savepoint'
$revision = $sp.revision
$apply = Invoke-OpnSenseApi -Config $Config -Method POST -Path "api/firewall/filter/apply/$revision"
Write-Host "    Applied revision $revision - confirming access..."
Start-Sleep -Seconds 3
try {
    $null = Invoke-OpnSenseApi -Config $Config -Method GET -Path 'api/core/firmware/status'
    $null = Invoke-OpnSenseApi -Config $Config -Method POST -Path "api/firewall/filter/cancelRollback/$revision"
    Write-Host "    Rollback cancelled (API still reachable)."
}
catch {
    Write-Warning "Could not confirm API after apply. Firewall may auto-rollback in ~60s."
    Write-Warning $_.Exception.Message
}

$state = [pscustomobject]@{
    appliedAt     = (Get-Date).ToString('o')
    wanRuleUuid   = $wanUuid
    wgRuleUuid    = $wgUuid
    wgInterface   = $wgIf
    tunnelNet     = $tunnelNet
    apply         = $apply
    revision      = $revision
}
$path = Write-StateJson -Name 'firewall.json' -Object $state
Write-Host "Saved $path"
Write-Host "Confirm in UI: Firewall -> Rules -> WAN (and WG interface) show the new rules."
Write-Host "Do NOT expose HTTPS/SSH management on WAN."
