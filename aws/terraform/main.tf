# =============================================================================
# Multi-Cloud APIM Gateway — AWS Terraform — main / locals / random
# =============================================================================

locals {
  prefix          = "${var.workload_name}-${var.environment_name}"
  lambda_zip_path = "${path.module}/.build/worldcup.zip"
}

resource "random_id" "suffix" {
  byte_length = 3
}

# Resolve Cognito domain prefix (must be globally unique per region)
locals {
  cognito_domain_prefix = length(var.cognito_domain_prefix) > 0 ? var.cognito_domain_prefix : "${local.prefix}-${random_id.suffix.hex}"
}

# Package the Lambda source into a zip on every plan/apply.
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/worldcup"
  output_path = local.lambda_zip_path
}
