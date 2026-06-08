// =============================================================================
// Multi-Cloud APIM Gateway — Named Values
// -----------------------------------------------------------------------------
// Purpose:
//   Centralises configuration values referenced from the APIM policy:
//     - tenantId               -> Entra tenant for JWT validation
//     - apimAudience           -> Expected JWT audience (e.g. api://apim-gateway)
//     - apimClientAppId        -> Expected azp/appid client app
//     - governedGroupObjectId  -> Optional Entra group used for group-level throttling
//     - environmentName        -> dev/test/prod (used in emit-metric dimensions)
//     - tokensPerMinuteUser    -> Per-user TPM
//     - tokensPerMinuteGroup   -> Per-group TPM
//     - tokenQuotaUserPerHour  -> Per-user hourly quota
//     - tokenQuotaGroupPerHour -> Per-group hourly quota
//
// Notes:
//   * NONE of these are marked `secret = true`; for true secrets, use a
//     Key Vault-backed Named Value (KeyVaultProperties) and grant APIM's
//     managed identity Key Vault Secrets User.
// =============================================================================

@description('Parent APIM instance name.')
param apimName string

@description('Entra tenant ID used for JWT validation.')
param tenantId string

@description('Expected JWT audience.')
param apimAudience string

@description('Expected JWT client application id (azp/appid claim).')
param apimClientAppId string

@description('Optional Entra group object id for group-level governance. Empty disables group rules.')
param governedGroupObjectId string = ''

@description('Logical environment name (dev/test/prod) used in emitted metric dimensions.')
param environmentName string

@description('Per-user tokens-per-minute limit.')
param tokensPerMinuteUser int = 1000

@description('Per-user hourly token quota.')
param tokenQuotaUserPerHour int = 20000

@description('Per-group tokens-per-minute limit (only applied if governedGroupObjectId is non-empty).')
param tokensPerMinuteGroup int = 5000

@description('Per-group hourly token quota.')
param tokenQuotaGroupPerHour int = 100000

resource apim 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimName
}

// Helper to declare a non-secret Named Value
@batchSize(1)
resource nvs 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = [for nv in [
  {
    name: 'tenantId'
    value: tenantId
  }
  {
    name: 'apimAudience'
    value: apimAudience
  }
  {
    name: 'apimClientAppId'
    value: apimClientAppId
  }
  {
    name: 'governedGroupObjectId'
    value: governedGroupObjectId
  }
  {
    name: 'environmentName'
    value: environmentName
  }
  {
    name: 'tokensPerMinuteUser'
    value: string(tokensPerMinuteUser)
  }
  {
    name: 'tokenQuotaUserPerHour'
    value: string(tokenQuotaUserPerHour)
  }
  {
    name: 'tokensPerMinuteGroup'
    value: string(tokensPerMinuteGroup)
  }
  {
    name: 'tokenQuotaGroupPerHour'
    value: string(tokenQuotaGroupPerHour)
  }
]: {
  name: nv.name
  parent: apim
  properties: {
    displayName: nv.name
    value: nv.value
    secret: false
  }
}]
