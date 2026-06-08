# Deployment walkthrough

A concrete end-to-end transcript of bringing the demo up. Times are approximate on a typical Azure / AWS account.

## Step 0 — Clone & prepare (≈ 2 min)

```powershell
git clone https://github.com/csdmichael/MultiCloud-APIM-Gateway.git
cd MultiCloud-APIM-Gateway
```

Install / verify tools per [implementation-guide.md §0](implementation-guide.md).

## Step 1 — Provision Entra app registration (≈ 10 min, one-time)

Follow [implementation-guide.md §1](implementation-guide.md#1-microsoft-entra-app-registration). Record:

| Var | Example |
| --- | --- |
| `TENANT_ID`     | `aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee` |
| `CLIENT_ID`     | `11111111-2222-3333-4444-555555555555` |
| `CLIENT_SECRET` | `abc.~Long~Secret~Value` |
| `AUDIENCE`      | `api://apim-gateway` |

Open `infra/bicep/main.dev.bicepparam` and paste these values:

```bicep
param tenantId         = '<TENANT_ID>'
param apimAudience     = 'api://apim-gateway'
param apimClientAppId  = '<CLIENT_ID>'
```

## Step 2 — Deploy Azure side (≈ 3 min when reusing APIM)

```powershell
az login
az account set --subscription 86b37969-9445-49cf-b03f-d8866235171c

# what-if first
.\scripts\deploy-azure.ps1 `
    -SubscriptionId 86b37969-9445-49cf-b03f-d8866235171c `
    -ResourceGroup ai-myaacoub `
    -WhatIf

# real deploy
.\scripts\deploy-azure.ps1 `
    -SubscriptionId 86b37969-9445-49cf-b03f-d8866235171c `
    -ResourceGroup ai-myaacoub
```

Verify the API exists:

```powershell
az apim api show --service-name apim-poc-my-dev `
    --resource-group ai-myaacoub --api-id worldcup-mocked `
    --query "{id:id, path:path, displayName:displayName}"
```

Expected gateway URL: `https://apim-poc-my-dev.azure-api.net/worldcup/teams`

## Step 3 — Deploy AWS side (≈ 4 min)

```bash
aws configure        # interactive, one-time
cd aws/terraform
cp dev.tfvars.example dev.auto.tfvars   # edit aws_region if needed

terraform init
terraform plan  -out tfplan
terraform apply tfplan
```

Sample apply output:

```
Apply complete! Resources: 14 added, 0 changed, 0 destroyed.

Outputs:
api_invoke_url             = "https://x9p8a7b6c5.execute-api.us-east-1.amazonaws.com"
api_teams_url              = "https://x9p8a7b6c5.execute-api.us-east-1.amazonaws.com/teams"
api_swagger_url            = "https://x9p8a7b6c5.execute-api.us-east-1.amazonaws.com/swagger"
cognito_token_url          = "https://mcgw-dev-a1b2c3.auth.us-east-1.amazoncognito.com/oauth2/token"
cognito_m2m_client_id      = "1abc23def45ghi67jkl89mno"
```

Get the M2M secret (kept out of state outputs):

```bash
aws cognito-idp describe-user-pool-client \
    --user-pool-id $(terraform output -raw cognito_user_pool_id) \
    --client-id   $(terraform output -raw cognito_m2m_client_id) \
    --query 'UserPoolClient.ClientSecret' --output text
```

## Step 4 — Smoke test APIM (≈ 30 sec)

```powershell
.\scripts\test-api.ps1 `
    -ApimHost apim-poc-my-dev.azure-api.net `
    -TenantId $env:TENANT_ID `
    -ClientId $env:CLIENT_ID `
    -ClientSecret $env:CLIENT_SECRET `
    -Audience api://apim-gateway
```

Expected output (abbreviated):

```
[1] 200 remaining-tokens=998
---- Body ----
{
  "tournament": "FIFA World Cup 2026",
  "host_countries": ["USA", "Canada", "Mexico"],
  ...
}
---- Headers ----
x-mcgw-user-oid: 11111111-2222-3333-4444-555555555555
x-mcgw-tenant: aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee
x-mcgw-user-tokens-remaining: 998
```

## Step 5 — Smoke test AWS (≈ 30 sec)

```bash
export APIM_HOST=$(terraform output -raw api_invoke_url | sed -E 's#https?://##')
export TENANT_ID=...
export AUDIENCE=https://mcgw-dev.api/read   # cognito resource server identifier + scope
export CLIENT_ID=$(terraform output -raw cognito_m2m_client_id)
export CLIENT_SECRET=...
../../examples/curl/valid-token.sh
```

(Or open `terraform output -raw api_swagger_url` in a browser.)

## Step 6 — Observability sanity check (≈ 5 min wait)

After making a handful of calls, paste the queries from [kql-queries.md](kql-queries.md) into App Insights → Logs. The "Top users by tokens consumed" and "Throttled responses over time" queries should both return rows.

## Step 7 — Demo flow (≈ 5 min)

1. Show a 200 + body.
2. Show the `x-mcgw-user-tokens-remaining` header counting down.
3. Run `test-api.ps1 -Burst 200` and let the audience see 429 with `Retry-After`.
4. Wait for the hour rollover or set `tokenQuotaUserPerHour` very low temporarily — show the 403 quota envelope.
5. Open App Insights and run the KQL queries.
6. Switch to AWS Swagger URL and show the same payload coming directly from Lambda.

## Step 8 — Cleanup

```powershell
# Azure - leaves shared APIM intact when useExistingApim=true
az apim api delete --service-name apim-poc-my-dev --resource-group ai-myaacoub --api-id worldcup-mocked --yes
```

```bash
cd aws/terraform
terraform destroy
```
