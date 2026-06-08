<#
.SYNOPSIS
    End-to-end test script for the APIM Multi-Cloud Gateway demo.

.DESCRIPTION
    1. Acquires a JWT (client_credentials or interactive).
    2. Calls GET /worldcup/teams on APIM with the token.
    3. Prints the response + select governance headers.
    4. Optionally bursts N calls to trigger 429/403 for the demo.

.EXAMPLE
    .\test-api.ps1 -ApimHost apim-poc-my-dev.azure-api.net `
                   -TenantId $env:TENANT -ClientId $env:CID -ClientSecret $env:SECRET `
                   -Audience api://apim-gateway

.EXAMPLE
    .\test-api.ps1 -ApimHost apim-poc-my-dev.azure-api.net -Interactive -TenantId $env:TENANT -Audience api://apim-gateway -Burst 200
#>

[CmdletBinding(DefaultParameterSetName = 'ClientCreds')]
param(
    [Parameter(Mandatory = $true)]
    [string]$ApimHost,

    [string]$ApiPath = '/worldcup/teams',

    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [Parameter(ParameterSetName = 'ClientCreds', Mandatory = $true)]
    [string]$ClientId,

    [Parameter(ParameterSetName = 'ClientCreds', Mandatory = $true)]
    [string]$ClientSecret,

    [Parameter(Mandatory = $true)]
    [string]$Audience,

    [Parameter(ParameterSetName = 'Interactive')]
    [switch]$Interactive,

    [int]$Burst = 1
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# 1) Acquire token
$tokenArgs = @{
    TenantId = $TenantId
    Audience = $Audience
}
if ($Interactive) { $tokenArgs['Interactive'] = $true }
else {
    $tokenArgs['ClientId'] = $ClientId
    $tokenArgs['ClientSecret'] = $ClientSecret
}
$token = & (Join-Path $scriptDir 'get-token.ps1') @tokenArgs
if (-not $token) { throw 'Token acquisition failed' }

$uri = "https://$ApimHost$ApiPath"
$headers = @{
    Authorization     = "Bearer $token"
    'x-correlation-id'= [guid]::NewGuid().ToString()
}

function Invoke-OneCall([int]$n) {
    try {
        $resp = Invoke-WebRequest -Method Get -Uri $uri -Headers $headers -UseBasicParsing -ErrorAction Stop
        $remaining = $resp.Headers['x-mcgw-user-tokens-remaining'] -as [string]
        Write-Host ("[{0}] {1} remaining-tokens={2}" -f $n, $resp.StatusCode, $remaining) -ForegroundColor Green
        if ($n -eq 1) {
            Write-Host "---- Body ----" -ForegroundColor Cyan
            $resp.Content | Out-String | Write-Host
            Write-Host "---- Headers ----" -ForegroundColor Cyan
            $resp.Headers.GetEnumerator() | Where-Object { $_.Key -like 'x-mcgw-*' -or $_.Key -in @('Retry-After', 'WWW-Authenticate') } |
                ForEach-Object { '{0}: {1}' -f $_.Key, ($_.Value -join ',') } |
                ForEach-Object { Write-Host $_ }
        }
    }
    catch {
        $code = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
        $retry = $null
        if ($_.Exception.Response) {
            $retry = $_.Exception.Response.Headers['Retry-After']
        }
        Write-Host ("[{0}] {1} retry-after={2}" -f $n, $code, $retry) -ForegroundColor Yellow
    }
}

for ($i = 1; $i -le $Burst; $i++) {
    Invoke-OneCall $i
}
