// =============================================================================
// Multi-Cloud APIM Gateway — API + Operation + Policy
// -----------------------------------------------------------------------------
// Purpose:
//   Creates the `worldcup-mocked` API on the existing APIM, attaches the
//   composed policy XML at the API scope, and exposes a single GET operation
//   `/teams` that returns the mocked World Cup 2026 JSON via return-response.
//
// Notes:
//   * The policy XML is supplied as a string from the parent template so it
//     can be loaded from /policies/apim-policy.xml via `loadTextContent`.
//   * `apiType = 'http'` is correct for both REST and the AI-Gateway LLM
//     policies (`llm-token-limit`, `llm-emit-token-metric`).
// =============================================================================

@description('Parent APIM instance name.')
param apimName string

@description('API id (used as the API path/name).')
param apiId string = 'worldcup-mocked'

@description('Display name for the API.')
param apiDisplayName string = 'World Cup 2026 (Mocked)'

@description('Path segment under the APIM gateway URL (e.g., `worldcup`).')
param apiPath string = 'worldcup'

@description('Inline policy XML for the API scope.')
param policyXml string

resource apim 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimName
}

resource api 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  name: apiId
  parent: apim
  properties: {
    displayName: apiDisplayName
    path: apiPath
    protocols: [
      'https'
    ]
    subscriptionRequired: false
    type: 'http'
    apiType: 'http'
  }
}

resource teamsOp 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  name: 'get-teams'
  parent: api
  properties: {
    displayName: 'Get World Cup 2026 Teams (mocked)'
    method: 'GET'
    urlTemplate: '/teams'
    description: 'Returns a hard-coded list of FIFA World Cup 2026 host countries, groups, and teams. No backend is called; identity-aware governance applied by APIM policy.'
    responses: [
      {
        statusCode: 200
        description: 'Mocked World Cup 2026 payload.'
        representations: [
          {
            contentType: 'application/json'
          }
        ]
      }
      {
        statusCode: 401
        description: 'Invalid or missing JWT.'
      }
      {
        statusCode: 403
        description: 'Quota exceeded for user/group.'
      }
      {
        statusCode: 429
        description: 'Rate / token limit exceeded.'
      }
    ]
  }
}

resource apiPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  name: 'policy'
  parent: api
  properties: {
    format: 'rawxml'
    value: policyXml
  }
  dependsOn: [
    teamsOp
  ]
}

output apiId string = api.id
output apiName string = api.name
output apiPath string = api.properties.path
