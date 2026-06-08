# Known limitations & next steps

## Known limitations (intentional, for the demo)

1. **No real LLM backend.** The APIM policy uses `<return-response>` to short-circuit with hardcoded World Cup 2026 JSON; no AWS Bedrock, OpenAI, or Anthropic API call is made. See [migration-to-bedrock.md](migration-to-bedrock.md) for the production diff.
2. **Cognito stands in for AWS SSO federation.** A full Entra ↔ AWS IAM Identity Center federation requires admin access to your tenant and to AWS Organizations. For the demo we use Cognito User Pool with both an interactive client and a machine-to-machine client.
3. **Internal VNET APIM is not internet-reachable by design.** The repo doesn't ship an App Gateway / front door for it. From a developer workstation you must call from inside the VNet (jumpbox, VPN, or self-hosted runner).
4. **Developer SKU only.** APIM Developer tier has *no SLA* and a single unit. Production should use Premium with at least 2 units, deployed multi-region, with availability zones.
5. **Token-limit estimation is approximate.** `llm-token-limit` with `estimate-prompt-tokens="true"` counts characters/4 as a rough proxy. Real prompt tokens differ per tokenizer (cl100k_base vs Llama vs Claude).
6. **Group claim format must be Group ID.** App registration's "Groups claim" must be set to *Group ID*; emitting `sAMAccountName` strings will break the `governedGroupObjectId` match.
7. **No secret rotation automation.** The Entra client secret + Cognito M2M secret are static. In production wire them to Key Vault + Secrets Manager and use managed identities where possible.
8. **AWS API Gateway CORS allows `*`.** Sufficient for Swagger UI demo; lock down `allow_origins` for production.
9. **No automated end-to-end test in CI.** GitHub Actions workflows only run what-if / plan + deploy. Adding a smoke `test-api.sh` step requires storing test credentials at the repo level — opt-in only.
10. **APIM Internal VNET takes ~30–45 min to provision greenfield.** Use the `useExistingApim=true` path for fast iterations.

## Recommended next steps (prioritised)

### Production hardening (do first)

1. **Move APIM to Premium SKU** in two regions with active-active gateway URL via Front Door / Traffic Manager.
2. **Wire Entra app secrets into Azure Key Vault** with APIM `<authentication-managed-identity>` for runtime fetch; rotate every 90 days.
3. **Add per-tenant quota** above per-user (counter-key=`tid`) to defend against single-tenant abuse.
4. **Switch `llm-token-limit` to response-token mode** once a real backend exists (drop `estimate-prompt-tokens`).
5. **Add `validate-jwt` for incoming caller assertions** (defence in depth — `validate-azure-ad-token` already does this but a custom `validate-jwt` allows additional claims).
6. **Add IP allow-list policy** (`<ip-filter>`) for known partner ranges.

### Observability

7. **Build an Azure Workbook** combining the KQL queries in [kql-queries.md](kql-queries.md).
8. **Pipe `customMetrics` to Log Analytics → Sentinel** for security analytics (e.g. impossible-travel detection on `oid` claim).
9. **Add Azure Monitor alerts** for `Outcome=Throttled` > 5% over 15 min, and `requests/duration p99 > 1s`.

### Identity

10. **Replace Cognito with AWS SSO / IAM Identity Center** federated to Entra so the same Entra JWT is accepted by both APIM and AWS API Gateway.
11. **Add a Lambda authorizer** in front of API Gateway that validates Entra JWTs directly (alternative to step 10 for accounts without IAM Identity Center).
12. **Issue managed identities** for any compute that calls the gateway from inside Azure.

### Cost & quota

13. **Pre-allocate Bedrock TPM/RPM quotas** before flipping the mock policy off; APIM cannot enforce more than the upstream actually allows.
14. **Tag resources** with `costCenter`, `owner`, `environment` (Bicep already passes `tags: { solution: 'MultiCloud-APIM-Gateway', environment: '<env>' }` — extend it).

### Developer experience

15. **Publish the OpenAPI spec to APIM Developer Portal** so consumers can self-onboard.
16. **Add a `policy-fragments.bicep` module** that registers each fragment in `/policies/fragments/` as an APIM Policy Fragment resource, then reference them from `apim-policy.xml` via `<include-fragment>`.
17. **Add API revisions + versions** (`v1`, `v2-bedrock`) so you can A/B test the mock vs the real backend without breaking consumers.
18. **Lint policies with `Set-AzApiManagementPolicy -Force`** in CI to catch typos before deploy.

### Multi-cloud expansion

19. **Add a GCP region** (Cloud Run + Identity Platform) and front it with the same APIM gateway to prove the federated identity story across three clouds.
20. **Add Anthropic / OpenAI direct backends** as second & third routes in APIM, then use `llm-token-limit` to enforce cross-vendor budgets per user.
