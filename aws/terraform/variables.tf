# =============================================================================
# Multi-Cloud APIM Gateway — AWS Terraform — variables
# =============================================================================

variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
  default     = "us-east-1"
}

variable "workload_name" {
  description = "Short workload name used in resource names (lowercase, [a-z0-9-])."
  type        = string
  default     = "mcgw"

  validation {
    condition     = can(regex("^[a-z0-9-]{2,16}$", var.workload_name))
    error_message = "workload_name must be 2-16 lowercase alphanumerics or dashes."
  }
}

variable "environment_name" {
  description = "Logical environment (dev/test/prod)."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "test", "prod"], var.environment_name)
    error_message = "environment_name must be one of dev/test/prod."
  }
}

variable "lambda_runtime" {
  description = "AWS Lambda runtime for the worldcup function."
  type        = string
  default     = "nodejs20.x"
}

variable "lambda_memory_mb" {
  description = "Memory allocation for the worldcup Lambda. Default 128 MB keeps a single invocation at 0.125 GB-s, so the 400,000 GB-s/month perpetual free tier covers ~3.2M invocations of 1s each."
  type        = number
  default     = 128
}

variable "lambda_timeout_seconds" {
  description = "Timeout for the worldcup Lambda. Default 3 s caps the GB-s blast radius if the function ever hangs (still well above the mocked handler's typical <50 ms runtime)."
  type        = number
  default     = 3
}

variable "cognito_domain_prefix" {
  description = "Cognito User Pool hosted-UI domain prefix. Must be globally unique within the region."
  type        = string
  # Default uses a random suffix appended in main.tf so demos don't collide.
  default     = ""
}

variable "cognito_callback_urls" {
  description = "Callback URLs registered on the Cognito app client (for OAuth code flow)."
  type        = list(string)
  default     = ["http://localhost:8080/callback"]
}

variable "cognito_logout_urls" {
  description = "Logout URLs registered on the Cognito app client."
  type        = list(string)
  default     = ["http://localhost:8080/"]
}

variable "create_machine_to_machine_client" {
  description = "Create a Cognito app client supporting OAuth2 client_credentials (no user). NOTE: M2M tokens are billed at $6 per 1,000 token requests with no free tier (Cognito pricing, Nov 2023+). Default is `false` so the baseline deploy stays inside perpetual free tier; flip to `true` only when you want to demo the M2M flow."
  type        = bool
  default     = false
}
