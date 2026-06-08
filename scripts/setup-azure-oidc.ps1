# Sets up Azure federated identity for GitHub Actions deploy-azure.yml
# Idempotent: safe to re-run.
[CmdletBinding()]
param(
    [string] $AppName = 'gha-MultiCloud-APIM-Gateway',
    [string] $Repo    = 'csdmichael/MultiCloud-APIM-Gateway',
    [string] $RgName  = 'ai-myaacoub'
)
$ErrorActionPreference = 'Stop'

function Run($desc, [scriptblock] $sb) {
    Write-Host ">> $desc" -ForegroundColor Cyan
    & $sb
}

# 1. App registration
$appId = az ad app list --display-name $AppName --query '[0].appId' -o tsv
if (-not $appId) {
    Run "Creating app registration '$AppName'" { $script:appId = az ad app create --display-name $AppName --query appId -o tsv }
} else {
    Write-Host "   App reg exists: $appId" -ForegroundColor DarkGray
}

# 2. Service principal
$spId = az ad sp list --filter "appId eq '$appId'" --query '[0].id' -o tsv
if (-not $spId) {
    Run "Creating service principal" { $script:spId = az ad sp create --id $appId --query id -o tsv }
} else {
    Write-Host "   SP exists: $spId" -ForegroundColor DarkGray
}

# 3. Federated credentials
$creds = @(
    @{ name='gha-main-branch';  subject="repo:${Repo}:ref:refs/heads/main" }
    @{ name='gha-env-dev';      subject="repo:${Repo}:environment:dev"     }
    @{ name='gha-pull-request'; subject="repo:${Repo}:pull_request"        }
)
$existing = az ad app federated-credential list --id $appId -o json | ConvertFrom-Json
foreach ($c in $creds) {
    $match = $existing | Where-Object { $_.subject -eq $c.subject }
    if ($match) {
        Write-Host "   FedCred '$($match.name)' already covers subject '$($c.subject)'" -ForegroundColor DarkGray
        continue
    }
    $payload = [pscustomobject]@{
        name        = $c.name
        issuer      = 'https://token.actions.githubusercontent.com'
        subject     = $c.subject
        description = "GitHub Actions $Repo - $($c.name)"
        audiences   = @('api://AzureADTokenExchange')
    } | ConvertTo-Json -Compress
    $tmp = New-TemporaryFile
    $payload | Out-File -FilePath $tmp -Encoding ascii
    Run "Creating fed-cred '$($c.name)'" { az ad app federated-credential create --id $appId --parameters "@$tmp" | Out-Null }
    Remove-Item $tmp -Force
}

# 4. RBAC: Contributor on RG
$rgId = az group show --name $RgName --query id -o tsv
$existingAssignment = az role assignment list --assignee $appId --scope $rgId --role Contributor --query '[0].id' -o tsv
if (-not $existingAssignment) {
    Run "Assigning Contributor on $RgName" { az role assignment create --assignee $appId --role Contributor --scope $rgId | Out-Null }
} else {
    Write-Host "   Contributor already assigned" -ForegroundColor DarkGray
}

# 5. GitHub secrets (these are identifiers, not credentials — OIDC is passwordless)
$tenantId = az account show --query tenantId -o tsv
$subId    = az account show --query id -o tsv
Run "Setting GitHub secret AZURE_CLIENT_ID"       { gh secret set AZURE_CLIENT_ID       --repo $Repo --body $appId    | Out-Null }
Run "Setting GitHub secret AZURE_TENANT_ID"       { gh secret set AZURE_TENANT_ID       --repo $Repo --body $tenantId | Out-Null }
Run "Setting GitHub secret AZURE_SUBSCRIPTION_ID" { gh secret set AZURE_SUBSCRIPTION_ID --repo $Repo --body $subId    | Out-Null }

# Summary
Write-Host ""
Write-Host "===== DONE =====" -ForegroundColor Green
Write-Host "AZURE_CLIENT_ID       = $appId"
Write-Host "AZURE_TENANT_ID       = $tenantId"
Write-Host "AZURE_SUBSCRIPTION_ID = $subId"
Write-Host "Scope                 = $rgId"
Write-Host ""
Write-Host "GitHub secrets set:" -ForegroundColor Cyan
gh secret list --repo $Repo | Where-Object { $_ -match 'AZURE_' }
