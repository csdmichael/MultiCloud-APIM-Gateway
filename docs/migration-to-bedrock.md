# Migration to AWS Bedrock (real backend)

When you're ready to swap the mocked World Cup payload for a live Bedrock + Anthropic / OpenAI on AWS call, almost all of the APIM policy stays unchanged — that's the point of the AI-gateway pattern.

## 1. What changes

| Layer | Today (mocked) | Production (Bedrock) |
| --- | --- | --- |
| APIM `apim-policy.xml` | `<return-response>` | `<set-backend-service>` + `<forward-request>` |
| APIM Backend | none | New `<backend>` pointing to AWS API Gateway invoke URL |
| AWS Lambda | returns hardcoded JSON | Bedrock client (`@aws-sdk/client-bedrock-runtime`) calling `InvokeModel` or `InvokeModelWithResponseStream` |
| `llm-token-limit` | `estimate-prompt-tokens="true"` | switch to parsing real `usage` block from the Bedrock response |
| Identity | Cognito JWT (demo IdP) | AWS SSO / IAM Identity Center JWT federated from Entra |

## 2. APIM policy diff

Replace the `<return-response>` block in `policies/apim-policy.xml` with:

```xml
<!-- 6. Real backend -->
<set-backend-service base-url="https://<aws-api-gateway-host>" />
<rewrite-uri template="/teams" copy-unmatched-params="true" />
<set-header name="x-mcgw-correlation-id" exists-action="override">
    <value>@(context.RequestId.ToString())</value>
</set-header>
```

…and keep everything else (jwt-validation, claims-extraction, llm-token-limit, llm-emit-token-metric, error-handlers) exactly as-is. Add an `<outbound>` block that adjusts `llm-token-limit` for real tokens:

```xml
<outbound>
    <base />
    <!-- llm-emit-token-metric will pick up actual usage from the response body -->
    <llm-emit-token-metric namespace="MultiCloudApimGateway">
        ...
    </llm-emit-token-metric>
</outbound>
```

> **`llm-token-limit` already supports the live mode**. Drop the `estimate-prompt-tokens="true"` attribute (or set it to `false`) once the backend's response contains a parseable `usage.prompt_tokens` / `usage.completion_tokens` payload. The policy auto-detects OpenAI and Bedrock response shapes.

## 3. Authentication between APIM and AWS

Two production-ready options:

### Option A — Signed AWS request (preferred)

* Use APIM **send-request** policy with `<authentication-managed-identity>` to mint an AWS access token via OIDC federation (Azure → AWS IAM via `sts:AssumeRoleWithWebIdentity`).
* Cache the AWS credentials in `<cache-lookup-value>` / `<cache-store-value>` for 50 minutes.
* Sign the outbound request with the SigV4 algorithm — APIM has a built-in `<authentication-managed-identity>` for Azure resources but for AWS you typically pass through a pre-signed bearer.

### Option B — Bearer pass-through

* AWS API Gateway accepts the Entra JWT directly via a Lambda authorizer that validates the OIDC discovery doc at `https://login.microsoftonline.com/{tenantId}/v2.0/.well-known/openid-configuration`.
* This is the simplest path and keeps the demo's identity model: one token, two clouds.

## 4. Lambda diff

Replace the `WORLD_CUP_PAYLOAD` constant + handler logic with:

```js
import { BedrockRuntimeClient, InvokeModelCommand } from '@aws-sdk/client-bedrock-runtime';

const client = new BedrockRuntimeClient({ region: process.env.AWS_REGION });

export const handler = async (event) => {
    const body = JSON.parse(event.body || '{}');
    const cmd = new InvokeModelCommand({
        modelId: 'anthropic.claude-3-sonnet-20240229-v1:0',
        contentType: 'application/json',
        accept: 'application/json',
        body: JSON.stringify({
            anthropic_version: 'bedrock-2023-05-31',
            messages: body.messages,
            max_tokens: 1024
        })
    });
    const resp = await client.send(cmd);
    return {
        statusCode: 200,
        headers: { 'Content-Type': 'application/json' },
        body: Buffer.from(resp.body).toString('utf-8')
    };
};
```

And in `iam.tf`, add a managed policy allowing `bedrock:InvokeModel` on the chosen model ARNs.

## 5. Cost & quota implications

* Bedrock charges per 1K input / output tokens; APIM `llm-token-limit` is your throttle of first resort.
* Update `tokensPerMinuteUser` / `tokenQuotaUserPerHour` Named Values based on your contracted Bedrock quota per region.
* Consider adding a **per-tenant** quota (counter-key=`tid`) above the per-user quota for noisy-neighbour protection.

## 6. Rollout sequence

1. Deploy this demo as-is (`return-response` mock).
2. Add a second API revision in APIM that points at the real AWS backend.
3. Use APIM **revisions** + **versions** to A/B test before flipping `current=true`.
4. Add an outbound `<llm-token-limit>` to re-evaluate the bucket using the actual response usage (will already auto-adjust if you remove `estimate-prompt-tokens`).
5. Switch identity from Cognito to Entra-only and decommission the Cognito user pool.

## 7. Where the demo already helps

You don't lose anything when you migrate — every artifact in this repo carries forward:

* Bicep stays (Internal VNET, NSG, Named Values, AppInsights).
* Policy stays (just the mock block changes).
* Test scripts stay (same JWT acquisition flow).
* App Insights / Log Analytics queries stay — the `customMetrics` schema is identical.
