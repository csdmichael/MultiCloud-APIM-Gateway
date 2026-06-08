# =============================================================================
# Multi-Cloud APIM Gateway — AWS Terraform — Cognito User Pool + clients
# -----------------------------------------------------------------------------
# This Cognito User Pool issues the JWTs that the API Gateway authorizer
# validates. In production AWS SSO (IAM Identity Center) is federated to
# Microsoft Entra ID; this pool stands in for that federation in the demo
# so reviewers can mint tokens without a tenant-wide change.
# =============================================================================

resource "aws_cognito_user_pool" "this" {
  name = "${local.prefix}-userpool"

  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 1
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  auto_verified_attributes = ["email"]

  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true
    string_attribute_constraints {
      min_length = 3
      max_length = 256
    }
  }

  admin_create_user_config {
    allow_admin_create_user_only = true
  }
}

resource "aws_cognito_user_pool_domain" "this" {
  domain       = local.cognito_domain_prefix
  user_pool_id = aws_cognito_user_pool.this.id
}

# ---------------------------------------------------------------------------
# Resource server: defines the `api` scope used by the M2M client below.
# ---------------------------------------------------------------------------
resource "aws_cognito_resource_server" "api" {
  identifier   = "https://${local.prefix}.api"
  name         = "${local.prefix}-api"
  user_pool_id = aws_cognito_user_pool.this.id

  scope {
    scope_name        = "read"
    scope_description = "Read access to the World Cup API"
  }
}

# ---------------------------------------------------------------------------
# Public client (used by Swagger UI / browser tests via OAuth code flow)
# ---------------------------------------------------------------------------
resource "aws_cognito_user_pool_client" "interactive" {
  name         = "${local.prefix}-interactive-client"
  user_pool_id = aws_cognito_user_pool.this.id

  generate_secret = false

  allowed_oauth_flows                  = ["code"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  callback_urls                        = var.cognito_callback_urls
  logout_urls                          = var.cognito_logout_urls
  supported_identity_providers         = ["COGNITO"]

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]

  prevent_user_existence_errors = "ENABLED"
  enable_token_revocation       = true

  access_token_validity  = 60
  id_token_validity      = 60
  refresh_token_validity = 30
  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }
}

# ---------------------------------------------------------------------------
# Machine-to-machine client (used by CI / curl examples to mint a JWT via
# the OAuth2 client_credentials grant without any user). Generates a secret.
# ---------------------------------------------------------------------------
resource "aws_cognito_user_pool_client" "m2m" {
  count = var.create_machine_to_machine_client ? 1 : 0

  name         = "${local.prefix}-m2m-client"
  user_pool_id = aws_cognito_user_pool.this.id

  generate_secret = true

  allowed_oauth_flows                  = ["client_credentials"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["${aws_cognito_resource_server.api.identifier}/read"]

  supported_identity_providers = ["COGNITO"]

  prevent_user_existence_errors = "ENABLED"
  enable_token_revocation       = true

  access_token_validity = 60
  token_validity_units {
    access_token = "minutes"
  }
}
