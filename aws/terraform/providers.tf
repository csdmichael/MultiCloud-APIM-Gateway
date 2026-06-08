# =============================================================================
# Multi-Cloud APIM Gateway — AWS Terraform — providers + backend
# -----------------------------------------------------------------------------
# Pin provider versions for reproducibility. The default backend is local; for
# team workflows uncomment the S3 + DynamoDB block and supply your own values.
# =============================================================================

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # backend "s3" {
  #   bucket         = "REPLACE-tfstate-bucket"
  #   key            = "multicloud-apim-gateway/aws/dev.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "REPLACE-tfstate-locks"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      solution    = "MultiCloud-APIM-Gateway"
      workload    = var.workload_name
      environment = var.environment_name
      managedBy   = "terraform"
    }
  }
}
