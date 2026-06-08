# GitHub Actions OIDC setup (Azure + AWS)

The two deployment workflows authenticate to their respective clouds via **OIDC** (no long-lived secrets). This folder contains the one-time setup automation.

## Azure (already done in this repo)

```powershell
.\scripts\setup-azure-oidc.ps1
```

Creates:

| Resource | Value |
| --- | --- |
| Entra app registration | `gha-MultiCloud-APIM-Gateway` |
| Federated credentials | `repo:csdmichael/MultiCloud-APIM-Gateway:ref:refs/heads/main`, `:environment:dev`, `:pull_request` |
| RBAC role assignment | `Contributor` on `/subscriptions/.../resourceGroups/ai-myaacoub` |
| GitHub repo secrets | `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` |

Idempotent — safe to re-run. Re-run after rotating the repo name or adding new environments.

## AWS (run on the box that has access to the AWS account)

This Windows workstation doesn't have AWS CLI installed, so the AWS side ships as a CloudFormation template + bash bootstrapper:

```bash
# On any machine signed in to AWS account csdmichael@hotmail.com with admin
./scripts/setup-aws-oidc.sh
# or pick a different region:
./scripts/setup-aws-oidc.sh --region us-west-2
# or skip the OIDC provider step if it already exists in the account:
./scripts/setup-aws-oidc.sh --skip-oidc-provider
```

Creates (via CloudFormation stack `multicloud-apim-gateway-github-oidc`):

| Resource | Value |
| --- | --- |
| IAM OIDC provider | `arn:aws:iam::<acct>:oidc-provider/token.actions.githubusercontent.com` (auto-skips if present) |
| IAM role | `GitHubActions-MultiCloudApimGateway` trusting the GitHub OIDC sub claims above |
| Managed policy | `*` on API Gateway / Lambda / Cognito / Logs, scoped IAM on `arn:aws:iam::<acct>:role/mcgw-*` |
| GitHub repo secret | `AWS_DEPLOY_ROLE_ARN` |

After the script finishes, both deployment workflows should succeed on the next run / PR.

### If you don't have AWS CLI handy

Install it:

```powershell
winget install -e --id Amazon.AWSCLI
aws configure          # or: aws sso login --profile <name>
```

Or open the CloudFormation template ([setup-aws-oidc.cfn.yaml](setup-aws-oidc.cfn.yaml)) directly in the AWS Console (CloudFormation → Create stack → Upload template) and create the stack with these parameters:

| Parameter | Value |
| --- | --- |
| `GitHubOrg` | `csdmichael` |
| `GitHubRepo` | `MultiCloud-APIM-Gateway` |
| `RoleName` | `GitHubActions-MultiCloudApimGateway` |
| `CreateOidcProvider` | `true` (or `false` if it exists) |

Copy the `RoleArn` output, then:

```powershell
gh secret set AWS_DEPLOY_ROLE_ARN --repo csdmichael/MultiCloud-APIM-Gateway --body "<paste arn here>"
```

## Verifying the secrets

```powershell
gh secret list --repo csdmichael/MultiCloud-APIM-Gateway
# Expected:
# AZURE_CLIENT_ID
# AZURE_TENANT_ID
# AZURE_SUBSCRIPTION_ID
# AWS_DEPLOY_ROLE_ARN
```

Trigger a run:

```powershell
gh workflow run deploy-azure.yml --repo csdmichael/MultiCloud-APIM-Gateway
gh workflow run deploy-aws.yml   --repo csdmichael/MultiCloud-APIM-Gateway
gh run watch --repo csdmichael/MultiCloud-APIM-Gateway
```
