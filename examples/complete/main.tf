# Complete example: deploys the pipeline with locally built Lambda packages.
#
# Build the packages first (see the companion app repo for the Lambda source):
#   pip install aws-durable-execution-sdk-python -t build/orchestrator
#   cp your_orchestrator.py build/orchestrator/lambda_function.py
#   (zip both directories, or let the archive_file data sources below do it)

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

provider "aws" {
  region = "us-east-1"
}

data "archive_file" "orchestrator" {
  type        = "zip"
  source_dir  = "${path.module}/build/orchestrator"
  output_path = "${path.module}/build/orchestrator.zip"
}

data "archive_file" "api" {
  type        = "zip"
  source_dir  = "${path.module}/build/api"
  output_path = "${path.module}/build/api.zip"
}

module "agent_pipeline" {
  source = "../.."

  project_name         = "durable-ai-agent-example"
  orchestrator_package = data.archive_file.orchestrator.output_path
  api_package          = data.archive_file.api.output_path

  model_id = "us.anthropic.claude-haiku-4-5-20251001-v1:0"

  tags = {
    Project = "durable-agent-pipeline-example"
  }
}

output "api_endpoint" {
  value = module.agent_pipeline.api_endpoint
}
