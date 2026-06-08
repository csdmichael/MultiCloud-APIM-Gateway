// =============================================================================
// Multi-Cloud APIM Gateway — Log Analytics Workspace
// -----------------------------------------------------------------------------
// Purpose:
//   Central log sink for Application Insights, APIM diagnostic logs, and any
//   future Azure resources in the demo.
//
// Notes:
//   * Workspace-based App Insights writes here; KQL queries in
//     docs/kql-queries.md target this workspace.
//   * SKU `PerGB2018` is the recommended modern SKU.
// =============================================================================

@description('Azure region for the workspace.')
param location string

@description('Log Analytics workspace name.')
param workspaceName string

@description('Retention in days for log data.')
@minValue(30)
@maxValue(730)
param retentionInDays int = 30

@description('Tags applied to the resource.')
param tags object = {}

resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

output id string = law.id
output customerId string = law.properties.customerId
output name string = law.name
