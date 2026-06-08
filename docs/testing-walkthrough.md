# Testing walkthrough

Reference for all the test artefacts in this repo, what each is for, and which response shape to expect.

## 1. Test matrix

| Scenario | Tool | Expected HTTP | Expected envelope |
| --- | --- | --- | --- |
| Valid Entra JWT | `examples/curl/valid-token.sh` or `scripts/test-api.ps1` | 200 | World Cup payload |
| Missing token | manual curl, no `Authorization` header | 401 | `{ "error": "unauthorized", "correlationId": "..." }` |
| Tampered token | `examples/curl/invalid-token.sh` | 401 | `{ "error": "unauthorized", ... }` |
| TPM exhaustion | `examples/curl/throttle-burst.sh` or `test-api.ps1 -Burst 60` | 429 + `Retry-After` | `{ "error": "rate_limited", ... }` |
| Quota exhaustion | `test-api.ps1 -Burst 500` over an hour OR temporarily lower `tokenQuotaUserPerHour` | 403 | `{ "error": "quota_exceeded", ... }` |
| AWS valid token | `examples/curl/valid-token.sh` against AWS host (alter `APIM_HOST` env) | 200 | World Cup payload |
| AWS missing token | `curl https://<aws>/teams` | 401 from API Gateway authorizer |
| AWS health | `curl https://<aws>/health` | 200 anonymous |

## 2. Running the scripts

### PowerShell (Windows / pwsh)

```powershell
# happy path
.\scripts\test-api.ps1 -ApimHost apim-poc-my-dev.azure-api.net `
    -TenantId $env:TENANT_ID -ClientId $env:CLIENT_ID -ClientSecret $env:CLIENT_SECRET `
    -Audience api://apim-gateway

# burst to trigger 429
.\scripts\test-api.ps1 ... -Burst 80

# interactive (user) token instead of client_credentials
.\scripts\test-api.ps1 -ApimHost apim-poc-my-dev.azure-api.net `
    -TenantId $env:TENANT_ID -Audience api://apim-gateway -Interactive
```

### Bash

```bash
export APIM_HOST=apim-poc-my-dev.azure-api.net
export TENANT_ID=...
export AUDIENCE=api://apim-gateway
export CLIENT_ID=...
export CLIENT_SECRET=...

# happy path
./scripts/test-api.sh
# burst
BURST=80 ./scripts/test-api.sh

# the dedicated curl examples
./examples/curl/valid-token.sh
./examples/curl/invalid-token.sh
COUNT=80 CONCURRENCY=8 ./examples/curl/throttle-burst.sh
```

### Postman collection

Import `examples/postman/MultiCloud-APIM-Gateway.postman_collection.json`. Set the collection variables (`tenantId`, `clientId`, `clientSecret`, `audience`, `apimHost`) and run the requests in order. The first request stores the token in a collection variable so subsequent calls can use it.

For the throttle demo, open the **Collection Runner**, pick the "APIM - Throttle burst" request, set iterations = 100, delay = 0 ms, then watch the response status flip from 200 → 429.

## 3. Observability validation (after testing)

Run these in App Insights → **Logs** (allow ~3 min for ingestion):

```kql
customMetrics
| where customDimensions.Namespace == "MultiCloudApimGateway"
| summarize total = sum(value) by tostring(customDimensions.UserName)
| top 10 by total desc
```

```kql
requests
| where url has "/worldcup/teams"
| summarize count() by resultCode, bin(timestamp, 1m)
| render timechart
```

```kql
requests
| where url has "/worldcup/teams" and resultCode == "429"
| project timestamp, resultCode, customDimensions
| top 50 by timestamp desc
```

See [kql-queries.md](kql-queries.md) for the full set.

## 4. Negative tests you should run before declaring "done"

* **Missing scope**: drop `scope=<audience>/.default`. Token will lack the audience; APIM should 401.
* **Wrong tenant**: get a token from a different tenant. APIM `<issuers>` mismatch should 401.
* **Group not configured**: request from a user not in the governed group. `customMetrics` `Group` dim should be `none`, request still 200.
* **Group configured**: request from a user in the governed group. `Group` dim should equal `<governedGroupObjectId>`; consuming the per-group bucket should result in 429 with a longer `Retry-After`.
* **Internal VNET reachability**: from outside the VNET, the gateway TCP-rejects you — confirms Internal VNET is in effect.

## 5. Performance baseline

Mocked path should be sub-30 ms p50 inside the VNet because the policy is the entire workload:

| Percentile | Expected |
| --- | --- |
| p50 | 15–30 ms |
| p95 | 50–80 ms |
| p99 | 150–250 ms |

Anything above 500 ms p99 in steady state means the JWT validation policy is hitting OIDC discovery for every request — check that App Insights `dependencies` table does **not** show calls to `login.microsoftonline.com` per request (APIM caches the OpenID config for 24h by default).

## 6. CI test loop

The provided GitHub Actions workflow `.github/workflows/deploy-azure.yml` runs `az deployment group what-if` on every PR and `az deployment group create` on `main`. The AWS one does `terraform fmt -check`, `terraform validate`, `terraform plan`, and (gated on `workflow_dispatch`) `terraform apply`.

You can add a post-deploy smoke step that invokes `scripts/test-api.sh` against the freshly deployed gateway; environment secrets `TENANT_ID`, `CLIENT_ID`, `CLIENT_SECRET`, `AUDIENCE` must be supplied at the org/repo level.
