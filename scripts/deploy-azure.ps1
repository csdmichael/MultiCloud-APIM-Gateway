<#
.SYNOPSIS
    Deploy the Azure side of the Multi-Cloud APIM Gateway via Bicep.

.DESCRIPTION
    Wraps `az deployment group what-if` and `az deployment group create` for
    `infra/bicep/main.bicep` against an existing or new resource group.

    Supports two paths:
      * Greenfield  - creates APIM, VNet, App Insights, Log Analytics
      * Brownfield  - reuses existing APIM (Bicep `useExistingApim=true`).

.EXAMPLE
    .\deploy-azure.ps1 -SubscriptionId 86b37969-9445-49cf-b03f-d8866235171c `
                       -ResourceGroup ai-myaacoub -Location eastus2 -WhatIf

.EXAMPLE
    .\deploy-azure.ps1 -SubscriptionId 86b37969-9445-49cf-b03f-d8866235171c `
                       -ResourceGroup ai-myaacoub -Location eastus2
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,

    [string]$Location = 'eastus2',

    [string]$ParametersFile = '../infra/bicep/main.dev.bicepparam',

    [string]$TemplateFile = '../infra/bicep/main.bicep',

    [switch]$WhatIf,

    [switch]$CreateResourceGroup
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$templatePath = Resolve-Path (Join-Path $scriptDir $TemplateFile)
$paramPath    = Resolve-Path (Join-Path $scriptDir $ParametersFile)

Write-Host "Setting subscription context: $SubscriptionId" -ForegroundColor Cyan
az account set --subscription $SubscriptionId | Out-Null

if ($CreateResourceGroup) {
    Write-Host "Ensuring resource group $ResourceGroup ($Location)..." -ForegroundColor Cyan
    az group create --name $ResourceGroup --location $Location | Out-Null
}

$deploymentName = "mcgw-{0:yyyyMMddHHmmss}" -f (Get-Date)

if ($WhatIf) {
    Write-Host "Running what-if for $templatePath ..." -ForegroundColor Yellow
    az deployment group what-if `
        --resource-group $ResourceGroup `
        --template-file $templatePath `
        --parameters $paramPath
    return
}

Write-Host "Deploying $deploymentName ..." -ForegroundColor Green
az deployment group create `
    --name $deploymentName `
    --resource-group $ResourceGroup `
    --template-file $templatePath `
    --parameters $paramPath `
    --output table

Write-Host "Outputs:" -ForegroundColor Green
az deployment group show `
    --resource-group $ResourceGroup `
    --name $deploymentName `
    --query properties.outputs
