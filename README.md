# terraform-aws-durable-agent-pipeline

[![CI](https://github.com/amrutp24/terraform-aws-durable-agent-pipeline/actions/workflows/ci.yml/badge.svg)](https://github.com/amrutp24/terraform-aws-durable-agent-pipeline/actions/workflows/ci.yml)
[![Registry](https://img.shields.io/badge/terraform-registry-844FBA?logo=terraform)](https://registry.terraform.io/modules/amrutp24/durable-agent-pipeline/aws)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Terraform module for a **human-in-the-loop AI agent pipeline** on AWS Lambda **durable functions** — the checkpoint/replay execution model AWS launched at re:Invent 2025 that lets a function suspend (for up to a year, at zero compute cost) and resume exactly where it left off.

The module provisions:

- A **durable Lambda function** (`durable_config` enabled, published version + `prod` alias — durable functions require qualified ARNs)
- A **plain API Lambda** behind an **API Gateway HTTP API** (`POST /posts`, `GET /posts/{id}`, `POST /posts/{id}/approve`)
- **DynamoDB** table for run status + pending-approval callback IDs
- **S3** bucket for published output
- **IAM** roles with least-privilege policies, including the two non-obvious grants durable functions need:
  - `AWSLambdaBasicDurableExecutionRolePolicy` on the orchestrator (checkpoint/replay permissions)
  - `lambda:SendDurableExecutionCallback*` on `"${function_arn}:*"` — callback ARNs are **sub-resources of the versioned function ARN**, so the bare function ARN never matches
- CloudWatch log groups with retention, and **reserved concurrency** limits as a cost guardrail

## Usage

```hcl
module "agent_pipeline" {
  source  = "amrutp24/durable-agent-pipeline/aws"
  version = "~> 1.1"

  project_name         = "durable-ai-agent"
  orchestrator_package = "${path.root}/build/orchestrator.zip" # bundle aws-durable-execution-sdk-python
  api_package          = "${path.root}/build/api.zip"          # bundle boto3 >= 1.40

  model_id                 = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
  callback_timeout_seconds = 86400
}

output "api_endpoint" {
  value = module.agent_pipeline.api_endpoint
}
```

The module deploys **pre-built zip packages** — your application code and its build stay in your repo. See [examples/complete](examples/complete) for a full working setup including the Lambda source code, or the companion app repo [`durable-ai-agent-pipeline`](https://github.com/amrutp24/durable-ai-agent-pipeline) this module was extracted from.

## Requirements

- **Terraform** >= 1.5
- **AWS provider** >= 6.25.0 — the first release with `durable_config` support
- **Random provider** >= 3.6.0

Bedrock **model access** must be granted for `model_id` in the deployment region (Bedrock console → Model access).

## Inputs

> Full list with types and defaults: see the **Inputs** tab on the Terraform Registry (generated from `variables.tf`).

**Required**

- **`orchestrator_package`** — path to the pre-built orchestrator zip. Must bundle `aws-durable-execution-sdk-python`.
- **`api_package`** — path to the pre-built API Lambda zip. Must bundle `boto3 >= 1.40` (for `SendDurableExecutionCallbackSuccess`).

**Common knobs** (all optional, sensible defaults)

- **`project_name`** — prefix for every resource name (default `durable-ai-agent`)
- **`model_id`** — Bedrock model / inference-profile ID (default Claude Haiku 4.5)
- **`lambda_alias_name`** — alias for the orchestrator's published version; durable functions must be invoked via a qualified ARN (default `prod`)
- **`max_revisions`** / **`approval_score_threshold`** — editor loop tuning (default `2` / `8`)
- **`callback_timeout_seconds`** — how long to wait for human approval (default `86400` = 24 h)
- **`durable_execution_timeout_seconds`** / **`durable_retention_period_days`** — durable execution lifetime and checkpoint history retention (default 48 h / 7 days)
- **`runtime`** / **`handler`** — Lambda runtime and handler (default `python3.13` / `lambda_function.lambda_handler`)
- **`orchestrator_reserved_concurrency`** / **`api_reserved_concurrency`** — cost guardrails, `-1` to disable (default `5` / `10`; use `-1` on accounts with a total concurrency limit ≤ 50)
- **`api_memory_mb`** / **`api_timeout_seconds`** — API Lambda sizing (default `256` / `30`)
- **`log_retention_days`** — CloudWatch retention (default `14`)
- **`tags`** — applied to all resources

## Outputs

- **`api_endpoint`** — base URL of the HTTP API
- **`orchestrator_qualified_arn`** — alias ARN; durable functions must be invoked through this, never the bare function name
- **`orchestrator_function_name`** / **`api_function_name`** — function names
- **`posts_bucket`** — output S3 bucket
- **`executions_table`** — DynamoDB status table
- **`orchestrator_role_arn`** — orchestrator execution role, for attaching extra permissions

## Cost notes

- Durable **waits are free** — no compute is billed while suspended.
- Reserved concurrency caps runaway invocation costs.
- DynamoDB is pay-per-request; log groups have finite retention.
- The dominant cost is Bedrock inference (~5–7 Haiku calls per pipeline run — a few cents).

## License

MIT
