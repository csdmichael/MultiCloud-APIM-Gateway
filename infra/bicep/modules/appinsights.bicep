// =============================================================================
// Multi-Cloud APIM Gateway — Application Insights (workspace-based)
// -----------------------------------------------------------------------------
// Purpose:
//   Receives APIM telemetry, including custom metrics emitted by the
//   `llm-emit-token-metric` policy. Underlying data lives in Log Analytics so
//   KQL queries in docs/kql-queries.md can use either AI or LAW workspaces.
// =============================================================================

@description('Azure region.')
param location string

@description('Application Insights resource name.')
param appInsightsName string

@description('Resource ID of the Log Analytics workspace to attach.')
param workspaceResourceId string

@description('Tags applied to the resource.')
param tags object = {}

resource ai 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  tags: tags
  properties: {
    Application_Type: 'web'
    Flow_Type: 'Bluefield'
    Request_Source: 'rest'
    WorkspaceResourceId: workspaceResourceId
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

output id string = ai.id
output name string = ai.name
output instrumentationKey string = ai.properties.InstrumentationKey
output connectionString string = ai.properties.ConnectionString
