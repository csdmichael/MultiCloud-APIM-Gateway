# =============================================================================
# Multi-Cloud APIM Gateway — AWS Terraform — outputs
# -----------------------------------------------------------------------------
# These outputs are surfaced to the README and to the GitHub Actions
# workflow so other systems (APIM smoke tests, Postman runs) can wire up.
# =============================================================================

output "api_invoke_url" {
  description = "Base invoke URL of the deployed HTTP API stage."
  value       = aws_apigatewayv2_api.http.api_endpoint
}

output "api_teams_url" {
  description = "Fully qualified URL of the World Cup teams endpoint."
  value       = "${aws_apigatewayv2_api.http.api_endpoint}/teams"
}

output "api_swagger_url" {
  description = "Fully qualified URL of the Swagger UI."
  value       = "${aws_apigatewayv2_api.http.api_endpoint}/swagger"
}

output "api_openapi_url" {
  description = "OpenAPI spec served by the Lambda."
  value       = "${aws_apigatewayv2_api.http.api_endpoint}/openapi.json"
}

output "cognito_issuer_url" {
  description = "OIDC issuer URL for the Cognito User Pool."
  value       = "https://cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.this.id}"
}

output "cognito_token_url" {
  description = "OAuth2 token endpoint (use with client_credentials grant)."
  value       = "https://${aws_cognito_user_pool_domain.this.domain}.auth.${var.aws_region}.amazoncognito.com/oauth2/token"
}

output "cognito_authorize_url" {
  description = "OAuth2 authorize endpoint (use for interactive / SSO flows)."
  value       = "https://${aws_cognito_user_pool_domain.this.domain}.auth.${var.aws_region}.amazoncognito.com/oauth2/authorize"
}

output "cognito_user_pool_id" {
  description = "Cognito User Pool id."
  value       = aws_cognito_user_pool.this.id
}

output "cognito_interactive_client_id" {
  description = "Client id of the interactive (code-flow) Cognito app client."
  value       = aws_cognito_user_pool_client.interactive.id
}

output "cognito_m2m_client_id" {
  description = "Client id of the machine-to-machine (client_credentials) app client."
  value       = var.create_machine_to_machine_client ? aws_cognito_user_pool_client.m2m[0].id : ""
}

# NOTE: the M2M client secret is NOT exposed as an output to keep it out of
# Terraform state diffs and CI logs. Retrieve it on demand with:
#   aws cognito-idp describe-user-pool-client \
#     --user-pool-id <pool-id> --client-id <client-id> \
#     --query 'UserPoolClient.ClientSecret' --output text
