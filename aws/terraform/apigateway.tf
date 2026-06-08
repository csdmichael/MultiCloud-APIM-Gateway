# =============================================================================
# Multi-Cloud APIM Gateway — AWS Terraform — API Gateway HTTP API
# -----------------------------------------------------------------------------
# Single HTTP API with:
#   * JWT authorizer (Cognito User Pool) on /teams, /swagger, /openapi.json
#   * /health route is unauthenticated for liveness probes
# Lambda integration uses payload format 2.0 (matches index.js `event.rawPath`).
# =============================================================================

resource "aws_apigatewayv2_api" "http" {
  name          = "${local.prefix}-worldcup-api"
  protocol_type = "HTTP"
  description   = "Mocked World Cup 2026 API protected by Cognito JWT."

  cors_configuration {
    allow_origins  = ["*"]
    allow_methods  = ["GET", "OPTIONS"]
    allow_headers  = ["Authorization", "Content-Type"]
    expose_headers = ["x-amzn-RequestId"]
    max_age        = 300
  }
}

# ---------- Lambda integration ----------
resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.worldcup.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

# ---------- JWT authorizer (Cognito) ----------
resource "aws_apigatewayv2_authorizer" "cognito_jwt" {
  api_id           = aws_apigatewayv2_api.http.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "${local.prefix}-cognito-jwt"

  jwt_configuration {
    # M2M client_credentials tokens use the resource server identifier as `aud`/audience.
    # User-flow tokens use the client_id. We include both.
    audience = compact([
      aws_cognito_user_pool_client.interactive.id,
      var.create_machine_to_machine_client ? aws_cognito_user_pool_client.m2m[0].id : ""
    ])
    issuer = "https://cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.this.id}"
  }
}

# ---------- Routes ----------
locals {
  authenticated_routes = {
    teams   = "GET /teams"
    swagger = "GET /swagger"
    spec    = "GET /openapi.json"
  }
}

resource "aws_apigatewayv2_route" "authed" {
  for_each           = local.authenticated_routes
  api_id             = aws_apigatewayv2_api.http.id
  route_key          = each.value
  target             = "integrations/${aws_apigatewayv2_integration.lambda.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito_jwt.id
}

resource "aws_apigatewayv2_route" "health" {
  api_id             = aws_apigatewayv2_api.http.id
  route_key          = "GET /health"
  target             = "integrations/${aws_apigatewayv2_integration.lambda.id}"
  authorization_type = "NONE"
}

# ---------- Stage ----------
resource "aws_cloudwatch_log_group" "apigw" {
  name              = "/aws/apigateway/${local.prefix}-worldcup"
  retention_in_days = 7 # keep storage well under the 5 GB perpetual free tier
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.apigw.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
      userAgent      = "$context.identity.userAgent"
    })
  }

  default_route_settings {
    throttling_burst_limit = 50
    throttling_rate_limit  = 100
  }
}
