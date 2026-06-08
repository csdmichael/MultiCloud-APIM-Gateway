// =============================================================================
// Multi-Cloud APIM Gateway — Azure API Management (Internal VNET)
// -----------------------------------------------------------------------------
// Purpose:
//   Provisions APIM in Internal VNET mode (Developer or Premium SKU) and
//   wires it to App Insights + Log Analytics for telemetry.
//
// Notes:
//   * Internal VNET integration requires Developer (single unit, no SLA) or
//     Premium (multi-region SLA). Use Developer for cost-effective demos.
//   * The service is assigned a SystemAssigned identity for Key Vault access
//     and platform-level RBAC.
//   * `apimLoggerForAppInsights` is the bridge that lets policies emit
//     telemetry into App Insights.
// =============================================================================

@description('Azure region.')
param location string

@description('APIM instance name (globally unique).')
param apimName string

@description('Publisher name shown in the developer portal.')
param publisherName string

@description('Publisher email used for notifications.')
param publisherEmail string

@description('APIM SKU. Use Developer for non-production, Premium for production with VNET integration.')
@allowed([
  'Developer'
  'Premium'
])
param sku string = 'Developer'

@description('Number of APIM units. Developer must be 1.')
@minValue(1)
@maxValue(12)
param capacity int = 1

@description('APIM subnet resource ID (must be in a VNet with the required NSG).')
param apimSubnetId string

@description('Application Insights resource ID.')
param appInsightsId string

@description('Application Insights instrumentation key (passed to the APIM logger).')
@secure()
param appInsightsInstrumentationKey string

@description('Tags applied to the resource.')
param tags object = {}

resource apim 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: apimName
  location: location
  tags: tags
  sku: {
    name: sku
    capacity: capacity
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherName: publisherName
    publisherEmail: publisherEmail
    virtualNetworkType: 'Internal'
    virtualNetworkConfiguration: {
      subnetResourceId: apimSubnetId
    }
    customProperties: {
      // Disable old TLS/SSL ciphers for hardened posture
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls10': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls11': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls10': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls11': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Ssl30': 'False'
    }
  }
}

// Logger that pushes APIM diagnostic + custom telemetry into App Insights
resource apimAppInsightsLogger 'Microsoft.ApiManagement/service/loggers@2024-05-01' = {
  name: 'appInsightsLogger'
  parent: apim
  properties: {
    loggerType: 'applicationInsights'
    description: 'Application Insights logger for APIM Multi-Cloud Gateway demo'
    resourceId: appInsightsId
    credentials: {
      instrumentationKey: appInsightsInstrumentationKey
    }
  }
}

// Service-wide diagnostic — emit request/response telemetry into the logger above
resource apimDiagnostic 'Microsoft.ApiManagement/service/diagnostics@2024-05-01' = {
  name: 'applicationinsights'
  parent: apim
  properties: {
    alwaysLog: 'allErrors'
    loggerId: apimAppInsightsLogger.id
    sampling: {
      samplingType: 'fixed'
      percentage: 100
    }
    frontend: {
      request: {
        headers: [
          'x-correlation-id'
        ]
        body: {
          bytes: 0
        }
      }
      response: {
        headers: [
          'x-ratelimit-remaining-tokens'
          'x-ratelimit-remaining-requests'
          'retry-after'
        ]
        body: {
          bytes: 0
        }
      }
    }
    backend: {
      request: {
        headers: []
        body: {
          bytes: 0
        }
      }
      response: {
        headers: []
        body: {
          bytes: 0
        }
      }
    }
  }
}

output apimId string = apim.id
output apimName string = apim.name
output apimPrincipalId string = apim.identity.principalId
output apimGatewayUrl string = apim.properties.gatewayUrl
output apimAppInsightsLoggerId string = apimAppInsightsLogger.id
