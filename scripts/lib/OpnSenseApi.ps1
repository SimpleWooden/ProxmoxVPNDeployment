# Shared OPNsense API helpers for this deployment kit.
# Dot-source from other scripts: . "$PSScriptRoot\lib\OpnSenseApi.ps1"

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Capture at dot-source time (caller $PSScriptRoot would be wrong inside functions).
$script:DeployLibDir = $PSScriptRoot

function Get-RepoRoot {
    Split-Path -Parent (Split-Path -Parent $script:DeployLibDir)
}

function Import-DeployConfig {
    param(
        [string]$Path = (Join-Path (Get-RepoRoot) 'config.ps1')
    )
    if (-not (Test-Path $Path)) {
        throw "Missing $Path - copy config.example.ps1 to config.ps1 and fill in values."
    }
    $cfg = & $Path
    if ($cfg -isnot [hashtable] -and $cfg -isnot [System.Collections.IDictionary]) {
        throw 'config.ps1 must return a hashtable.'
    }
    foreach ($required in @('OpnSenseUrl', 'ApiKey', 'ApiSecret', 'VpnHostname', 'WgLanCidr')) {
        if ([string]::IsNullOrWhiteSpace([string]$cfg[$required])) {
            throw "config.ps1 missing required value: $required"
        }
    }
    if ($cfg.ApiKey -match 'PASTE_' -or $cfg.ApiSecret -match 'PASTE_') {
        throw 'config.ps1 still has PASTE_ placeholders for API credentials.'
    }
    return $cfg
}

function Get-PythonExe {
    $venvPy = Join-Path (Get-RepoRoot) '.venv\Scripts\python.exe'
    if (Test-Path $venvPy) { return $venvPy }
    throw 'Python venv missing. Run: scripts\00-prereq-check.ps1'
}

function New-WgKeyPair {
    $py = Get-PythonExe
    $script = Join-Path $script:DeployLibDir 'wgkeys.py'
    $json = & $py $script
    if ($LASTEXITCODE -ne 0) { throw 'wgkeys.py failed' }
    return ($json | ConvertFrom-Json)
}

function Invoke-OpnSenseApi {
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [Parameter(Mandatory)][ValidateSet('GET', 'POST')]$Method,
        [Parameter(Mandatory)][string]$Path,
        [object]$Body = $null
    )

    $uri = ($Config.OpnSenseUrl.TrimEnd('/') + '/' + $Path.TrimStart('/'))
    $pair = '{0}:{1}' -f $Config.ApiKey, $Config.ApiSecret
    $basic = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($pair))

    $headers = @{
        Authorization = "Basic $basic"
        Accept        = 'application/json'
    }

    $params = @{
        Uri             = $uri
        Method          = $Method
        Headers         = $headers
        UseBasicParsing = $true
    }

    if ($null -ne $Body) {
        $params.ContentType = 'application/json'
        $params.Body = ($Body | ConvertTo-Json -Depth 12 -Compress)
    }

    if ($Config.SkipTlsVerify) {
        if ($PSVersionTable.PSVersion.Major -ge 7) {
            $params.SkipCertificateCheck = $true
        }
        else {
            if (-not ([System.Management.Automation.PSTypeName]'TrustAllCertsPolicy').Type) {
                $certPolicy = @'
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
  public bool CheckValidationResult(ServicePoint s, X509Certificate c, WebRequest r, int p) { return true; }
}
'@
                Add-Type -TypeDefinition $certPolicy
            }
            [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        }
    }

    try {
        $resp = Invoke-RestMethod @params
    }
    catch {
        $msg = $_.Exception.Message
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
            $msg = "$msg | $($_.ErrorDetails.Message)"
        }
        throw "OPNsense API $Method $Path failed: $msg"
    }
    return $resp
}

function Write-StateJson {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Object
    )
    $dir = Join-Path (Get-RepoRoot) 'state'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    $path = Join-Path $dir $Name
    ($Object | ConvertTo-Json -Depth 12) | Set-Content -Path $path -Encoding UTF8
    return $path
}

function Read-StateJson {
    param([Parameter(Mandatory)][string]$Name)
    $path = Join-Path (Join-Path (Get-RepoRoot) 'state') $Name
    if (-not (Test-Path $path)) { return $null }
    return (Get-Content -Raw $path | ConvertFrom-Json)
}

function Resolve-DynDnsServiceName {
    param([hashtable]$Config)
    if (-not [string]::IsNullOrWhiteSpace([string]$Config.DynDnsService)) {
        return [string]$Config.DynDnsService
    }
    switch ([string]$Config.DynDnsProvider.ToLowerInvariant()) {
        'cloudflare' { return 'Cloudflare' }
        'namecheap'  { return 'NameCheap' }
        'duckdns'    { return 'Duck DNS' }
        'godaddy'    { return 'GoDaddy' }
        'dynu'       { return 'Dynu' }
        'noip'       { return 'no-ip' }
        default {
            throw "Unknown DynDnsProvider '$($Config.DynDnsProvider)'. Set DynDnsService to the exact OPNsense label."
        }
    }
}
