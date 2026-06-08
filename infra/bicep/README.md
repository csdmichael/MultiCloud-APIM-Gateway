# `infra/bicep` — Azure infrastructure for the Multi-Cloud APIM Gateway demo

This folder provisions every Azure resource needed for the demo:

| Module | Resource |
| --- | --- |
| `modules/loganalytics.bicep` | Log Analytics workspace |
| `modules/appinsights.bicep`  | Workspace-based Application Insights |
| `modules/vnet.bicep`         | VNet + subnet + APIM-required NSG |
| `modules/apim.bicep`         | Azure API Management (Internal VNET) + diagnostic + AI logger |
| `modules/namedvalues.bicep`  | APIM Named Values consumed by the policy |
| `modules/apim-api.bicep`     | `worldcup-mocked` API + GET `/teams` + policy XML |

`main.bicep` composes them and supports two modes:

1. **Reuse an existing APIM** — `useExistingApim = true` / `existingApimName = 'apim-poc-my-dev'`
   Skips VNet + APIM creation and only attaches Named Values + the new API/policy.
   This is the default in [`main.dev.bicepparam`](main.dev.bicepparam) so the demo wires into the APIM referenced in [`/docs/Prompts.txt`](../../docs/Prompts.txt).
2. **Create a fresh APIM** — flip `useExistingApim` to `false` and provide DNS-safe `workloadName` / `environmentName`. APIM in Internal VNET mode takes ~30–40 minutes the first time.

## Deploy

```powershell
# 1) Edit infra/bicep/main.dev.bicepparam — set tenantId, apimAudience, apimClientAppId
code infra/bicep/main.dev.bicepparam

# 2) Deploy (Bicep ≥ 0.27 recommended)
az deployment group create `
  --resource-group ai-myaacoub `
  --template-file infra/bicep/main.bicep `
  --parameters infra/bicep/main.dev.bicepparam
```

## What-if before deploy

```powershell
az deployment group what-if `
  --resource-group ai-myaacoub `
  --template-file infra/bicep/main.bicep `
  --parameters infra/bicep/main.dev.bicepparam
```

## Secrets

No secrets are stored in the templates or parameter files. For real secrets, swap any `namedValue` to a Key Vault–backed Named Value and grant APIM's system-assigned identity `Key Vault Secrets User`.
