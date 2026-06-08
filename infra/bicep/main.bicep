// =============================================================================
// Multi-Cloud APIM Gateway — Main Bicep
// -----------------------------------------------------------------------------
// Purpose:
//   Orchestrates all modules: Log Analytics → App Insights → VNet/NSG →
//   APIM (Internal VNET) → Named Values → API + Policy.
//
// Usage:
//   az deployment group create \
//     --resource-group ai-myaacoub \
//     --template-file infra/bicep/main.bicep \
//     --parameters infra/bicep/main.dev.bicepparam
//
// Notes:
//   * The policy XML is loaded at compile time from /policies/apim-policy.xml
//     using `loadTextContent`. Re-deploy after editing the policy.
//   * NONE of the parameters are secrets; safe values can live in .bicepparam.
//     For real secrets, wire them via Key Vault-backed Named Values.
// =============================================================================

targetScope = 'resourceGroup'

// ---------- Required parameters ----------
@description('Azure region (e.g., eastus2).')
param location string = resourceGroup().location

@description('Workload / environment short name. Used in resource names. Lower-case alphanumerics only.')
@minLength(2)
@maxLength(10)
param workloadName string

@description('Logical environment name (dev/test/prod). Used in resource names and metric dimensions.')
@allowed([
  'dev'
  'test'
  'prod'
])
param environmentName string = 'dev'

@description('APIM publisher name.')
param publisherName string

@description('APIM publisher email.')
param publisherEmail string

@description('APIM SKU (Developer or Premium for Internal VNET).')
@allowed([
  'Developer'
  'Premium'
])
param apimSku string = 'Developer'

@description('APIM unit count.')
@minValue(1)
@maxValue(12)
param apimCapacity int = 1

// ---------- JWT / governance parameters ----------
@description('Entra tenant ID used by validate-azure-ad-token.')
param tenantId string

@description('Expected JWT audience value (e.g., api://apim-gateway).')
param apimAudience string

@description('Expected JWT client application id (azp/appid).')
param apimClientAppId string

@description('Optional Entra group object id for group-level governance.')
param governedGroupObjectId string = ''

@description('Per-user tokens-per-minute limit.')
param tokensPerMinuteUser int = 1000

@description('Per-user hourly token quota.')
param tokenQuotaUserPerHour int = 20000

@description('Per-group tokens-per-minute limit.')
param tokensPerMinuteGroup int = 5000

@description('Per-group hourly token quota.')
param tokenQuotaGroupPerHour int = 100000

// ---------- Optional reuse parameters ----------
@description('If true, reuse the APIM instance referenced by `existingApimName`.')
param useExistingApim bool = false

@description('Existing APIM instance name (used when useExistingApim = true).')
param existingApimName string = ''

// ---------- Derived names ----------
var lawName  = 'log-${workloadName}-${environmentName}'
var aiName   = 'appi-${workloadName}-${environmentName}'
var vnetName = 'vnet-${workloadName}-${environmentName}'
var apimNameDerived = 'apim-${workloadName}-${environmentName}'
var apimName = useExistingApim && !empty(existingApimName) ? existingApimName : apimNameDerived

var commonTags = {
  workload: workloadName
  environment: environmentName
  solution: 'MultiCloud-APIM-Gateway'
  managedBy: 'bicep'
}

// ---------- Log Analytics ----------
module law 'modules/loganalytics.bicep' = {
  name: 'deploy-law'
  params: {
    location: location
    workspaceName: lawName
    tags: commonTags
  }
}

// ---------- Application Insights ----------
module ai 'modules/appinsights.bicep' = {
  name: 'deploy-ai'
  params: {
    location: location
    appInsightsName: aiName
    workspaceResourceId: law.outputs.id
    tags: commonTags
  }
}

// ---------- VNet + NSG (only when creating a fresh APIM) ----------
module vnet 'modules/vnet.bicep' = if (!useExistingApim) {
  name: 'deploy-vnet'
  params: {
    location: location
    vnetName: vnetName
    tags: commonTags
  }
}

// ---------- APIM (only when not reusing) ----------
module apim 'modules/apim.bicep' = if (!useExistingApim) {
  name: 'deploy-apim'
  params: {
    location: location
    apimName: apimName
    publisherName: publisherName
    publisherEmail: publisherEmail
    sku: apimSku
    capacity: apimCapacity
    apimSubnetId: vnet!.outputs.apimSubnetId
    appInsightsId: ai.outputs.id
    appInsightsInstrumentationKey: ai.outputs.instrumentationKey
    tags: commonTags
  }
}

// ---------- Named Values (attached to the APIM, new or existing) ----------
module namedValues 'modules/namedvalues.bicep' = {
  name: 'deploy-namedvalues'
  params: {
    apimName: apimName
    tenantId: tenantId
    apimAudience: apimAudience
    apimClientAppId: apimClientAppId
    governedGroupObjectId: governedGroupObjectId
    environmentName: environmentName
    tokensPerMinuteUser: tokensPerMinuteUser
    tokenQuotaUserPerHour: tokenQuotaUserPerHour
    tokensPerMinuteGroup: tokensPerMinuteGroup
    tokenQuotaGroupPerHour: tokenQuotaGroupPerHour
  }
  dependsOn: useExistingApim ? [] : [
    apim
  ]
}

// ---------- API + Policy ----------
module worldcupApi 'modules/apim-api.bicep' = {
  name: 'deploy-worldcup-api'
  params: {
    apimName: apimName
    apiId: 'worldcup-mocked'
    apiDisplayName: 'World Cup 2026 (Mocked)'
    apiPath: 'worldcup'
    policyXml: loadTextContent('../../policies/apim-policy.xml')
  }
  dependsOn: [
    namedValues
  ]
}

// ---------- Outputs ----------
output apimResourceName string = apimName
output apimGatewayBase string = useExistingApim
  ? 'https://${apimName}.azure-api.net'
  : apim!.outputs.apimGatewayUrl
output apiPath string = worldcupApi.outputs.apiPath
output appInsightsName string = ai.outputs.name
output logAnalyticsName string = law.outputs.name
