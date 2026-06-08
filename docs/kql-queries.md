# KQL queries — App Insights / Log Analytics

All queries assume the App Insights workspace populated by the APIM `appInsightsLogger` created in `infra/bicep/modules/apim.bicep`.

The custom metric namespace is **`MultiCloudApimGateway`**. Dimensions emitted by `llm-emit-token-metric`:

| Dimension | Source |
| --- | --- |
| `UserId` | `oid` claim |
| `UserName` | `preferred_username` or `upn` |
| `TenantId` | `tid` claim |
| `Group` | first entry of `groupsCsv`, or `none` |
| `Environment` | Bicep param `environmentName` |
| `ApiName` | `worldcup-mocked` |
| `Outcome` | `Success` / `Throttled` / `QuotaExceeded` / `Unauthorized` |

Open the App Insights resource in the portal → **Logs** → paste any of the following.

---

## 1. Top users by tokens consumed

```kql
customMetrics
| where name == "TokensConsumed" and customDimensions.Namespace == "MultiCloudApimGateway"
| extend user = tostring(customDimensions.UserName)
| summarize tokens = sum(value) by user
| top 10 by tokens desc
```

## 2. Top groups by tokens consumed

```kql
customMetrics
| where name == "TokensConsumed" and customDimensions.Namespace == "MultiCloudApimGateway"
| extend grp = tostring(customDimensions.Group)
| where grp != "none"
| summarize tokens = sum(value) by grp
| top 10 by tokens desc
```

## 3. Throttled (429) responses

```kql
requests
| where url has "/worldcup/teams" and resultCode == "429"
| extend correlationId = tostring(customDimensions.["x-correlation-id"])
| project timestamp, resultCode, correlationId, duration, customDimensions
| top 100 by timestamp desc
```

## 4. Quota-exceeded (403) responses

```kql
requests
| where url has "/worldcup/teams" and resultCode == "403"
| project timestamp, resultCode, duration, customDimensions
| top 100 by timestamp desc
```

## 5. Token usage over time (5-min bins)

```kql
customMetrics
| where name == "TokensConsumed" and customDimensions.Namespace == "MultiCloudApimGateway"
| summarize tokens = sum(value) by bin(timestamp, 5m)
| render timechart
```

## 6. Usage by API + environment

```kql
customMetrics
| where customDimensions.Namespace == "MultiCloudApimGateway"
| extend api = tostring(customDimensions.ApiName),
         env = tostring(customDimensions.Environment)
| summarize tokens = sum(value) by api, env
| order by tokens desc
```

## 7. Outcome distribution

```kql
customMetrics
| where customDimensions.Namespace == "MultiCloudApimGateway"
| extend outcome = tostring(customDimensions.Outcome)
| summarize n = count() by outcome
| render piechart
```

## 8. p50 / p95 latency by hour

```kql
requests
| where url has "/worldcup/teams"
| summarize p50 = percentile(duration, 50), p95 = percentile(duration, 95) by bin(timestamp, 1h)
| render timechart
```

## 9. Recent 401s with reason

```kql
requests
| where url has "/worldcup/teams" and resultCode == "401"
| project timestamp, resultCode, customDimensions, operation_Name
| top 50 by timestamp desc
```

## 10. Correlate a single request end-to-end

If you captured `x-correlation-id` on the client, paste it here:

```kql
let cid = "<paste-correlation-id>";
union requests, traces, exceptions, customMetrics
| where customDimensions.["x-correlation-id"] == cid
   or operation_Id == cid
| order by timestamp asc
```

---

## Workbook-ready KQL pack

You can pin the above into an Azure Monitor Workbook with a parameter `Environment` and `ApiName`:

```kql
customMetrics
| where customDimensions.Namespace == "MultiCloudApimGateway"
| where customDimensions.Environment == '{Environment}'
| where customDimensions.ApiName == '{ApiName}'
| summarize tokens = sum(value) by bin(timestamp, 5m), tostring(customDimensions.UserName)
| render timechart
```
