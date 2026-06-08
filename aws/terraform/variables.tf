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
  description = "Memory allocation for the worldcup Lambda."
  type        = number
  default     = 256
}

variable "lambda_timeout_seconds" {
  description = "Timeout for the worldcup Lambda."
  type        = number
  default     = 5
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
  description = "Create a Cognito app client supporting OAuth2 client credentials (no user)."
  type        = bool
  default     = true
}
