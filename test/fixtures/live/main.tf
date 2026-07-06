# Live-test root: deploys the module with the behavioral-test fixtures.
# Driven by test/module_test.go (TestDurableLifecycle); not for manual use.

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.25.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4.0"
    }
  }
}

variable "aws_region" {
  description = "Region to run the behavioral test in."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Unique per-test-run prefix, passed by the Go test."
  type        = string
}

provider "aws" {
  region = var.aws_region
}

data "archive_file" "orchestrator" {
  type        = "zip"
  source_dir  = "${path.module}/../build/orchestrator"
  output_path = "${path.module}/../build/orchestrator.zip"
}

data "archive_file" "api" {
  type        = "zip"
  source_dir  = "${path.module}/../build/api"
  output_path = "${path.module}/../build/api.zip"
}

module "pipeline" {
  source = "../../.."

  project_name         = var.project_name
  orchestrator_package = data.archive_file.orchestrator.output_path
  api_package          = data.archive_file.api.output_path

  # Fixture never calls Bedrock; short lifetimes keep test debris cheap
  durable_execution_timeout_seconds = 3600
  durable_retention_period_days     = 1
  log_retention_days                = 1
  callback_timeout_seconds          = 600

  orchestrator_reserved_concurrency = -1
  api_reserved_concurrency          = -1

  tags = {
    Purpose = "terratest-behavioral"
  }
}

output "orchestrator_qualified_arn" {
  value = module.pipeline.orchestrator_qualified_arn
}

output "executions_table" {
  value = module.pipeline.executions_table
}

output "posts_bucket" {
  value = module.pipeline.posts_bucket
}
