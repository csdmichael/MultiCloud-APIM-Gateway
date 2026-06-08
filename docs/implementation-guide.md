# Implementation Guide

This guide walks through, in order, every step required to stand the demo up from a clean machine.

## 0. Prerequisites

| Tool | Min version | Notes |
| --- | --- | --- |
| Azure CLI | 2.60+ | `az bicep upgrade` recommended |
| Bicep CLI | 0.28+ | bundled with Azure CLI |
| Terraform | 1.7+ | use 1.9 if possible |
| AWS CLI | 2.15+ | profile with `AdministratorAccess` on the demo account |
| Node.js | 20.x | needed only if you want to run the Lambda locally |
| PowerShell | 7.4+ on Linux/macOS, 5.1+ on Windows | scripts in `scripts/` |
| `jq`, `curl`, `uuidgen` | latest | bash scripts in `examples/` |

You also need:

* An Azure subscription (this demo defaults to `86b37969-9445-49cf-b03f-d8866235171c` / RG `ai-myaacoub`).
* Permissions to create app registrations in your Entra tenant (`Application.ReadWrite.All` or higher).
* An AWS account (`csdmichael@hotmail.com`) with rights to create Cognito, API Gateway, Lambda, IAM, CloudWatch.

## 1. Microsoft Entra: app registration

1. In the Azure portal → **Microsoft Entra ID → App registrations → New registration**.
   * Name: `apim-gateway-demo`
   * Supported account types: *single tenant*
2. **Expose an API → Add a scope** with Application ID URI `api://apim-gateway`. Add a scope `access_as_user`.
3. **App roles → Create app role** (used for the client_credentials grant we test with): `name=Reader`, `value=Worldcup.Read`, allowed for `Applications`.
4. **Token configuration → Add groups claim** → *Security groups* (or *Groups assigned to the application* for less leakage). Select **Group ID** for the `groups` claim format. Apply for ID + Access tokens.
5. **API permissions → Add a permission** → "My APIs" → `apim-gateway-demo` → Application permissions → `Worldcup.Read`. **Grant admin consent**.
6. **Certificates & secrets → New client secret**. Save the value; you'll need it in `dev.tfvars` / `.bicepparam`.

Collect:

| Value | Used as |
| --- | --- |
| Directory (tenant) ID | `tenantId` Bicep param |
| Application (client) ID | `apimClientAppId` Bicep param |
| Application ID URI | `apimAudience` Bicep param (`api://apim-gateway`) |
| Optional governed group object id | `governedGroupObjectId` Bicep param |

## 2. Azure: deploy Bicep

### Option A — reuse an existing APIM instance

The provided `main.dev.bicepparam` sets `useExistingApim=true` and `existingApimName=apim-poc-my-dev`. Only the API definition, policy, named values, and observability resources are deployed; the APIM service itself is untouched.

### Option B — greenfield (creates VNet + APIM + AppInsights + LAW)

Set `useExistingApim=false` and pick a workload/environment name. APIM Internal VNET takes ~30–45 minutes to provision the first time.

```powershell
# from repo root
.\scripts\deploy-azure.ps1 `
    -SubscriptionId 86b37969-9445-49cf-b03f-d8866235171c `
    -ResourceGroup ai-myaacoub `
    -Location eastus2 `
    -WhatIf

# When the what-if looks right:
.\scripts\deploy-azure.ps1 `
    -SubscriptionId 86b37969-9445-49cf-b03f-d8866235171c `
    -ResourceGroup ai-myaacoub `
    -Location eastus2
```

The resulting deployment outputs include the APIM resource name, gateway base URL, API path, App Insights name, and Log Analytics workspace name.

> **Tip.** If you greenfield-deploy a brand-new Internal VNET APIM, you cannot reach it from the public internet. Either deploy a jumpbox VM into the VNet or use an Application Gateway in front. For the demo we strongly recommend reusing the existing `apim-poc-my-dev` instance.

## 3. AWS: deploy Terraform

```bash
cd aws/terraform
cp dev.tfvars.example dev.auto.tfvars   # edit if you want different defaults

terraform init
terraform plan -out tfplan
terraform apply tfplan

# Capture the outputs into env vars for the test scripts
eval "$(terraform output -json \
    | jq -r 'to_entries[] | "export TF_OUT_\(.key | ascii_upcase)=\(.value.value | @sh)"')"
```

Key outputs:

* `api_teams_url` — `https://<id>.execute-api.<region>.amazonaws.com/teams`
* `api_swagger_url` — `https://<id>.execute-api.<region>.amazonaws.com/swagger`
* `cognito_token_url` — `https://<prefix>.auth.<region>.amazoncognito.com/oauth2/token`
* `cognito_m2m_client_id` — used with `client_credentials` to mint test JWTs

Retrieve the M2M client secret (not exported by Terraform):

```bash
aws cognito-idp describe-user-pool-client \
    --user-pool-id "$(terraform output -raw cognito_user_pool_id)" \
    --client-id "$(terraform output -raw cognito_m2m_client_id)" \
    --query 'UserPoolClient.ClientSecret' --output text
```

## 4. Smoke test

### APIM (Azure)

```powershell
.\scripts\test-api.ps1 `
    -ApimHost apim-poc-my-dev.azure-api.net `
    -TenantId <tenant-id> `
    -ClientId <entra-app-client-id> `
    -ClientSecret <entra-app-secret> `
    -Audience api://apim-gateway
```

Expected output:

* `HTTP/1.1 200`
* JSON body containing the World Cup 2026 host countries, total matches, etc.
* Headers `x-mcgw-user-tokens-remaining`, `x-mcgw-user-oid`, `x-mcgw-tenant`.

### Throttle / quota demo

```powershell
.\scripts\test-api.ps1 ... -Burst 200
```

Watch the `remaining` value go to zero, then 429 responses with `Retry-After` headers. Continue, and once the per-hour bucket is exhausted, you'll see 403 with `{ "error": "quota_exceeded" }`.

### AWS

```bash
export APIM_HOST=$(terraform output -raw api_invoke_url | sed -E 's#https?://##')
export TENANT_ID=...
export AUDIENCE=https://mcgw-dev.api/read
export CLIENT_ID=$(terraform output -raw cognito_m2m_client_id)
export CLIENT_SECRET=...
./examples/curl/valid-token.sh
```

## 5. Observability

Logged automatically via the APIM AppInsights logger created in `apim.bicep`:

* `requests` — gateway HTTP calls
* `dependencies` — only present when the policy calls a backend (none in the mocked path)
* `customMetrics` — emitted by `llm-emit-token-metric` with dimensions

See [kql-queries.md](kql-queries.md) for ready-to-paste queries.

## 6. Tearing down

```powershell
# Azure
az deployment group delete --name <deployment-name> --resource-group ai-myaacoub
# (the API resource alone — leaves shared APIM / VNet intact when useExistingApim=true)

# AWS
cd aws/terraform; terraform destroy
```
