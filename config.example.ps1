# Copy to config.ps1 and fill in your values.
# Never commit config.ps1 (it is gitignored).

@{
    # OPNsense management (LAN)
    OpnSenseUrl      = 'https://192.168.0.1'
    # System → Access → Users → (user) → API keys
    ApiKey           = 'PASTE_API_KEY'
    ApiSecret        = 'PASTE_API_SECRET'
    SkipTlsVerify    = $true   # self-signed cert on LAN is common

    # Dynamic DNS
    VpnHostname      = 'vpn.example.com'   # FQDN clients will dial
    DnsZone          = 'example.com'       # zone/apex (Cloudflare "Zone")
    # cloudflare | namecheap | duckdns | godaddy | other
    # For "other", set DynDnsService to the exact OPNsense service label
    # (e.g. 'Cloudflare', 'NameCheap', 'Duck DNS', 'GoDaddy').
    DynDnsProvider   = 'cloudflare'
    DynDnsService    = ''                  # leave blank to auto-map from provider
    DynDnsUsername   = 'token'             # Cloudflare API token: literal "token"
    DynDnsPassword   = 'PASTE_DNS_TOKEN'   # Cloudflare API token / provider secret
    DynDnsCheckIp    = 'if'                # use WAN interface address
    DynDnsInterface  = 'wan'
    DynDnsInterval   = 300

    # WireGuard
    WgInstanceName   = 'home'
    WgTunnelCidr     = '10.10.10.1/24'
    WgListenPort     = 51820
    WgLanCidr        = '192.168.0.0/22'    # client AllowedIPs (LAN only)
    WgDns            = '192.168.0.1'       # optional DNS pushed to clients

    # Peer inventory file (copy peers.example.json → peers.json)
    PeersFile        = 'peers.json'
}
