// =============================================================================
// Multi-Cloud APIM Gateway — Dev environment parameters
// -----------------------------------------------------------------------------
// Pre-filled to target the APIM instance referenced in /docs/Prompts.txt:
//   subscription : 86b37969-9445-49cf-b03f-d8866235171c
//   resourceGroup: ai-myaacoub
//   apim         : apim-poc-my-dev      (reused via useExistingApim = true)
//
// Replace the JWT-related placeholders with real values for your tenant.
// =============================================================================

using './main.bicep'

param workloadName     = 'mcgw'
param environmentName  = 'dev'
param location         = 'eastus2'

param publisherName    = 'Multi-Cloud APIM Demo'
param publisherEmail   = 'apim-admin@example.com'

param apimSku          = 'Developer'
param apimCapacity     = 1

// ---- Reuse the existing APIM specified in /docs/Prompts.txt ----
param useExistingApim  = true
param existingApimName = 'apim-poc-my-dev'

// ---- JWT validation parameters (TODO: replace before deploying) ----
param tenantId          = '00000000-0000-0000-0000-000000000000'
param apimAudience      = 'api://apim-gateway'
param apimClientAppId   = '00000000-0000-0000-0000-000000000000'
param governedGroupObjectId = ''

// ---- Governance limits ----
param tokensPerMinuteUser    = 1000
param tokenQuotaUserPerHour  = 20000
param tokensPerMinuteGroup   = 5000
param tokenQuotaGroupPerHour = 100000
