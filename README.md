# terraform-aws-durable-agent-pipeline

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
  version = "~> 1.0"

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

| Name | Version |
|------|---------|
| terraform | >= 1.5 |
| aws | >= 6.25.0 (first release with `durable_config`) |
| random | >= 3.6.0 |

Bedrock **model access** must be granted for `model_id` in the deployment region (Bedrock console → Model access).

## Inputs

| Name | Description | Default |
|------|-------------|---------|
| `project_name` | Prefix for all resource names | `"durable-ai-agent"` |
| `orchestrator_package` | Path to pre-built orchestrator zip (must bundle the durable execution SDK) | — (required) |
| `api_package` | Path to pre-built API Lambda zip | — (required) |
| `runtime` | Lambda runtime (durable functions: python3.13/3.14, nodejs22/24, java17/21/25) | `"python3.13"` |
| `handler` | Lambda handler for both functions | `"lambda_function.lambda_handler"` |
| `lambda_alias_name` | Alias pointing at the latest published orchestrator version (durable functions require qualified ARNs) | `"prod"` |
| `api_memory_mb` / `api_timeout_seconds` | API Lambda sizing | `256` / `30` |
| `model_id` | Bedrock model / inference-profile ID | Claude Haiku 4.5 |
| `max_revisions` | Max writer/editor loops before human approval | `2` |
| `approval_score_threshold` | Editor score that ends the revision loop | `8` |
| `callback_timeout_seconds` | How long to wait for human approval | `86400` |
| `durable_execution_timeout_seconds` | Max total execution lifetime | `172800` |
| `durable_retention_period_days` | Checkpoint history retention (1–90) | `7` |
| `orchestrator_reserved_concurrency` | Cost guardrail; `-1` to disable | `5` |
| `api_reserved_concurrency` | Cost guardrail; `-1` to disable | `10` |
| `log_retention_days` | CloudWatch retention | `14` |
| `tags` | Tags for all resources | `{}` |

## Outputs

| Name | Description |
|------|-------------|
| `api_endpoint` | Base URL of the HTTP API |
| `orchestrator_qualified_arn` | `prod` alias ARN — durable functions must be invoked via qualified ARN |
| `orchestrator_function_name` | Orchestrator function name |
| `api_function_name` | API function name |
| `posts_bucket` | Output S3 bucket |
| `executions_table` | DynamoDB status table |
| `orchestrator_role_arn` | Orchestrator execution role (for extending permissions) |

## Cost notes

- Durable **waits are free** — no compute is billed while suspended.
- Reserved concurrency caps runaway invocation costs.
- DynamoDB is pay-per-request; log groups have finite retention.
- The dominant cost is Bedrock inference (~5–7 Haiku calls per pipeline run — a few cents).

## License

MIT
