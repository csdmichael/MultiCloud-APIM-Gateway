<#
.SYNOPSIS
    Acquires a Microsoft Entra ID JWT for calling the APIM Multi-Cloud Gateway demo.

.DESCRIPTION
    Wraps Azure CLI to perform OAuth 2.0 client_credentials. The resulting access
    token must:
      * have audience matching the APIM Named Value {{apimAudience}}
      * be issued by the tenant configured in {{tenantId}}
      * carry the application id matching {{apimClientAppId}}

    For an interactive (user) login that produces an `oid` claim, use the
    `-Interactive` switch — that triggers `az login` device-code flow scoped
    to the same audience.

.PARAMETER TenantId
    Entra tenant id.

.PARAMETER ClientId
    Application (client) id of the calling app registration.

.PARAMETER ClientSecret
    Client secret for client_credentials. Required when -Interactive is NOT set.

.PARAMETER Audience
    The 'aud' the access token should be issued for. Typically `api://apim-gateway`.

.PARAMETER Interactive
    If specified, performs an interactive `az account get-access-token` (for the
    currently logged in az user) to acquire a user-context token with oid/upn.

.EXAMPLE
    .\get-token.ps1 -TenantId <guid> -ClientId <guid> -ClientSecret <secret> -Audience api://apim-gateway

.EXAMPLE
    .\get-token.ps1 -TenantId <guid> -Audience api://apim-gateway -Interactive
#>

[CmdletBinding(DefaultParameterSetName = 'ClientCreds')]
param(
    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [Parameter(ParameterSetName = 'ClientCreds', Mandatory = $true)]
    [string]$ClientId,

    [Parameter(ParameterSetName = 'ClientCreds', Mandatory = $true)]
    [string]$ClientSecret,

    [Parameter(Mandatory = $true)]
    [string]$Audience,

    [Parameter(ParameterSetName = 'Interactive')]
    [switch]$Interactive
)

$ErrorActionPreference = 'Stop'

function Get-AzureAdTokenInteractive {
    param([string]$Tenant, [string]$Resource)
    # Reuses cached az login if present; otherwise device-code prompts the user.
    $tokenJson = az account get-access-token --tenant $Tenant --resource $Resource --output json 2>$null
    if (-not $tokenJson) {
        Write-Host "No active az login for tenant $Tenant — launching device-code login..." -ForegroundColor Yellow
        az login --tenant $Tenant --allow-no-subscriptions --use-device-code | Out-Null
        $tokenJson = az account get-access-token --tenant $Tenant --resource $Resource --output json
    }
    return ($tokenJson | ConvertFrom-Json).accessToken
}

function Get-AzureAdTokenClientCreds {
    param(
        [string]$Tenant,
        [string]$AppId,
        [string]$AppSecret,
        [string]$Resource
    )
    $body = @{
        client_id     = $AppId
        client_secret = $AppSecret
        grant_type    = 'client_credentials'
        scope         = "$Resource/.default"
    }
    $uri = "https://login.microsoftonline.com/$Tenant/oauth2/v2.0/token"
    $resp = Invoke-RestMethod -Method Post -Uri $uri -Body $body -ContentType 'application/x-www-form-urlencoded'
    return $resp.access_token
}

$token = if ($Interactive) {
    Get-AzureAdTokenInteractive -Tenant $TenantId -Resource $Audience
} else {
    Get-AzureAdTokenClientCreds -Tenant $TenantId -AppId $ClientId -AppSecret $ClientSecret -Resource $Audience
}

if (-not $token) { throw "Failed to acquire JWT" }

# Emit only the token to STDOUT so callers can pipe / capture:
#   $jwt = .\get-token.ps1 ...
$token
