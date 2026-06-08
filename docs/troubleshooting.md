# Troubleshooting

## A. APIM returns 401 `unauthorized` for what looks like a valid token

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `Bearer error="invalid_token"` + `error_description="The audience..."`  | Token `aud` ≠ APIM Named Value `apimAudience` | Re-mint the token using `scope=<apimAudience>/.default` (client_credentials) or set the resource correctly for `az account get-access-token --resource` |
| `error="invalid_token", error_description="The token is expired"` | Clock skew or genuinely expired | Re-acquire; Entra tokens default to 60–75 min |
| `error_description="Signature validation failed"` | Token signed by wrong tenant | Confirm `tid` claim matches the configured `tenantId` Named Value |
| 401 with no body | Token missing entirely or wrong `Authorization` header format | Header must be exactly `Authorization: Bearer <token>` |

Check the actual JWT contents at <https://jwt.ms> (Microsoft-run, does NOT verify signature).

## B. APIM returns 401 from `on-error`, but `validate-azure-ad-token` looks fine

The most common cause is `<required-claims>` mismatch: a claim listed there is missing from the access token. Either:

* Adjust the app registration (see `docs/implementation-guide.md` step 1.3–1.4).
* Relax the policy by removing the offending `<required-claim>`.

## C. APIM 429 `rate_limited`, even on the first call

* The `llm-token-limit` counter persists per APIM unit. If the previous run consumed the bucket and the minute hasn't rolled, you'll still see 429.
* The header `x-mcgw-user-tokens-remaining` shows current state.
* Raise the limit by updating the Named Value `tokensPerMinuteUser` (no redeploy needed):

```bash
az apim nv update --service-name apim-poc-my-dev --resource-group ai-myaacoub \
    --named-value-id tokensPerMinuteUser --value 5000
```

## D. APIM 403 `quota_exceeded`

Per-hour quota tracked by `tokenQuotaUserPerHour`. Resets at the top of every clock hour. Either wait or raise the Named Value. Note that 403 and 429 are distinguished by checking `x-mcgw-user-tokens-consumed` against the configured per-hour quota inside `on-error`.

## E. App Insights `customMetrics` table is empty

1. Confirm the APIM diagnostic logger exists: portal → APIM → **Diagnostic settings** → `appInsightsLogger` should be enabled and pointing at the App Insights workspace.
2. There is a 2–5 minute ingestion delay before metrics appear.
3. The `llm-emit-token-metric` policy must run; if `return-response` runs *before* it, the metric is never emitted. In this repo, `llm-emit-token-metric` is intentionally placed before `return-response` for that reason.
4. KQL filter: `customMetrics | where customDimensions.Namespace == "MultiCloudApimGateway"`.

## F. Bicep `useExistingApim=true` deployment fails with `ResourceNotFound`

The named APIM service does not exist in the resource group. Either:

* Set `existingApimName` to the correct service name.
* Set `useExistingApim=false` to create one greenfield (Internal VNET takes ~30–45 min).

## G. Bicep deployment fails on `apim-api.bicep` with conflict

The API `worldcup-mocked` already exists under a different path or display name. Delete it manually or change `apiName` in `main.bicep`:

```bash
az apim api delete --service-name apim-poc-my-dev --resource-group ai-myaacoub --api-id worldcup-mocked
```

## H. JWT requests fail with 401 when only the interactive client is deployed

With `create_machine_to_machine_client = false` (the free-tier-safe default)
no M2M app client is created and the authorizer's `audience` list contains
only the interactive client id. M2M `client_credentials` token requests will
fail because the issuer has no M2M client to mint them against. To enable
the M2M flow:

* Set `create_machine_to_machine_client = true` and `terraform apply`.
  Note: Cognito charges $6 per 1,000 M2M token requests with no free tier.
* Or add the audience of an externally-managed app client to the `audience`
  list in `apigateway.tf` and `terraform apply`.

## I. Lambda returns 502 from API Gateway

* Look in `/aws/lambda/<prefix>-worldcup` CloudWatch log group for the stack trace.
* The Lambda uses payload format **v2.0** — `event.rawPath` and `event.requestContext.http.method`. If you swap the integration to AWS_PROXY v1.0 you have to rewrite `index.js`.

## J. Cognito token endpoint returns 400 `invalid_client`

* The M2M client secret is wrong, or the client doesn't have `client_credentials` allowed.
* Re-read the secret with `aws cognito-idp describe-user-pool-client ...` (see implementation guide §3).
* Authorization header must be `Basic base64(client_id:client_secret)`. Postman's "Basic Auth" tab handles that.

## K. AWS API Gateway returns 401 `Unauthorized` immediately

Token `aud` claim must match the `audience` list configured on the authorizer. By default that list contains the interactive client id and (optionally) the M2M client id. If you generated the token with a different client, add it to the list and `terraform apply`.

## L. Swagger UI page loads but "Try it out" returns 401

The UI reads `localStorage.authToken` and stuffs it into the `Authorization` header. Open dev-tools console and run:

```js
localStorage.setItem('authToken', '<your jwt>')
```

then re-issue the request. (A production version would integrate Cognito Hosted UI.)

## M. `az deployment group create` is slow on first run

Bicep CLI installs ~30 MB of binaries the first time. Re-runs are fast.

## N. APIM in Internal VNET is unreachable from a workstation

By design — the gateway has no public IP. Options:
* Self-hosted runner / dev VM inside the same VNet.
* App Gateway with public IP fronting APIM.
* Azure VPN / Private Link.
