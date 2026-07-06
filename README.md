# terraform-aws-durable-agent-pipeline

[![CI](https://github.com/amrutp24/terraform-aws-durable-agent-pipeline/actions/workflows/ci.yml/badge.svg)](https://github.com/amrutp24/terraform-aws-durable-agent-pipeline/actions/workflows/ci.yml)
[![Registry](https://img.shields.io/badge/terraform-registry-844FBA?logo=terraform)](https://registry.terraform.io/modules/amrutp24/durable-agent-pipeline/aws)
[![License: Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

Terraform module for a **human-in-the-loop AI agent pipeline** on AWS Lambda **durable functions** — the checkpoint/replay execution model AWS launched at re:Invent 2025 that lets a function suspend (for up to a year, at zero compute cost) and resume exactly where it left off.

The module provisions:

- A **durable Lambda function** (`durable_config` enabled, published version + alias — durable functions require qualified ARNs)
- A **plain API Lambda** behind an **API Gateway HTTP API** (`POST /posts`, `GET /posts/{id}`, `POST /posts/{id}/approve`)
- **DynamoDB** table for run status + pending-approval callback IDs
- **S3** bucket (SSE, versioned, public access blocked) for published output
- **IAM** roles with least-privilege policies, including the two non-obvious grants durable functions need:
  - `AWSLambdaBasicDurableExecutionRolePolicy` on the orchestrator (checkpoint/replay permissions)
  - `lambda:SendDurableExecutionCallback*` on `"${function_arn}:*"` — callback ARNs are **sub-resources of the versioned function ARN**, so the bare function ARN never matches
- CloudWatch log groups with retention, and **reserved concurrency** limits as a cost guardrail

## Usage

### Minimal

```hcl
module "agent_pipeline" {
  source  = "amrutp24/durable-agent-pipeline/aws"
  version = "~> 1.2"

  orchestrator_package = "${path.root}/build/orchestrator.zip" # bundle aws-durable-execution-sdk-python
  api_package          = "${path.root}/build/api.zip"          # bundle boto3 >= 1.40
}
```

### Tuned pipeline with a different model and longer approval window

```hcl
module "agent_pipeline" {
  source  = "amrutp24/durable-agent-pipeline/aws"
  version = "~> 1.2"

  project_name         = "content-review"
  orchestrator_package = "${path.root}/build/orchestrator.zip"
  api_package          = "${path.root}/build/api.zip"

  model_id                 = "us.anthropic.claude-sonnet-4-5-v1:0"
  max_revisions            = 3
  approval_score_threshold = 9

  callback_timeout_seconds          = 259200 # 3 days for a human to respond
  durable_execution_timeout_seconds = 345600 # 4 days total lifetime
}
```

### Locked-down API (SigV4) with custom sizing

```hcl
module "agent_pipeline" {
  source  = "amrutp24/durable-agent-pipeline/aws"
  version = "~> 1.2"

  orchestrator_package = "${path.root}/build/orchestrator.zip"
  api_package          = "${path.root}/build/api.zip"

  api_authorization_type = "AWS_IAM" # callers must sign requests

  orchestrator_memory_mb            = 1024
  orchestrator_reserved_concurrency = 20
  api_reserved_concurrency          = 50
  log_retention_days                = 90

  tags = {
    Team = "platform"
  }
}
```

The module deploys **pre-built zip packages** — your application code and its build stay in your repo. See [examples/complete](examples/complete) for a full working setup, or the companion app repo [`durable-ai-agent-pipeline`](https://github.com/amrutp24/durable-ai-agent-pipeline) this module was extracted from.

Bedrock **model access** must be granted for `model_id` in the deployment region (Bedrock console → Model access) if your orchestrator calls Bedrock.

## Cost notes

- Durable **waits are free** — no compute is billed while suspended.
- Reserved concurrency caps runaway invocation costs.
- DynamoDB is pay-per-request; log groups have finite retention.
- The dominant cost is Bedrock inference (~5–7 Haiku calls per pipeline run — a few cents).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.25.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 3.6.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.25.0 |
| <a name="provider_random"></a> [random](#provider\_random) | >= 3.6.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_apigatewayv2_api.http_api](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_api) | resource |
| [aws_apigatewayv2_integration.api](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_integration) | resource |
| [aws_apigatewayv2_route.approve](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_route) | resource |
| [aws_apigatewayv2_route.start](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_route) | resource |
| [aws_apigatewayv2_route.status](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_route) | resource |
| [aws_apigatewayv2_stage.default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_stage) | resource |
| [aws_cloudwatch_log_group.api](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_log_group.orchestrator](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_dynamodb_table.executions](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table) | resource |
| [aws_iam_role.api](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.orchestrator](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.api_inline](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.orchestrator_inline](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.api_basic](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.orchestrator_basic](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.orchestrator_durable](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_lambda_alias.orchestrator_prod](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_alias) | resource |
| [aws_lambda_function.api](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function) | resource |
| [aws_lambda_function.orchestrator](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function) | resource |
| [aws_lambda_permission.apigw_invoke_api](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_permission) | resource |
| [aws_s3_bucket.posts](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_public_access_block.posts](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.posts](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.posts](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [random_id.bucket_suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/id) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.lambda_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_api_package"></a> [api\_package](#input\_api\_package) | Path to the pre-built zip for the API Lambda (must bundle a boto3 recent enough for SendDurableExecutionCallbackSuccess). | `string` | n/a | yes |
| <a name="input_orchestrator_package"></a> [orchestrator\_package](#input\_orchestrator\_package) | Path to the pre-built zip for the durable orchestrator Lambda (must bundle aws-durable-execution-sdk-python). | `string` | n/a | yes |
| <a name="input_api_authorization_type"></a> [api\_authorization\_type](#input\_api\_authorization\_type) | Authorization type for the HTTP API routes. NONE keeps the demo self-contained; AWS\_IAM requires SigV4-signed requests. | `string` | `"NONE"` | no |
| <a name="input_api_memory_mb"></a> [api\_memory\_mb](#input\_api\_memory\_mb) | Memory for the API Lambda. | `number` | `256` | no |
| <a name="input_api_reserved_concurrency"></a> [api\_reserved\_concurrency](#input\_api\_reserved\_concurrency) | Reserved concurrent executions for the API Lambda. Set -1 for unreserved. | `number` | `10` | no |
| <a name="input_api_timeout_seconds"></a> [api\_timeout\_seconds](#input\_api\_timeout\_seconds) | Per-invocation timeout for the API Lambda. | `number` | `30` | no |
| <a name="input_approval_score_threshold"></a> [approval\_score\_threshold](#input\_approval\_score\_threshold) | Editor score (1-10) at or above which the draft is considered good enough. | `number` | `8` | no |
| <a name="input_callback_timeout_seconds"></a> [callback\_timeout\_seconds](#input\_callback\_timeout\_seconds) | How long the orchestrator waits for human approval before giving up. | `number` | `86400` | no |
| <a name="input_durable_execution_timeout_seconds"></a> [durable\_execution\_timeout\_seconds](#input\_durable\_execution\_timeout\_seconds) | Max total lifetime of one durable execution (steps + waits combined). Max 1 year. | `number` | `172800` | no |
| <a name="input_durable_retention_period_days"></a> [durable\_retention\_period\_days](#input\_durable\_retention\_period\_days) | How long Lambda retains checkpoint/execution history after completion (1-90). | `number` | `7` | no |
| <a name="input_handler"></a> [handler](#input\_handler) | Lambda handler for both functions (module.function format matching your packaged code). | `string` | `"lambda_function.lambda_handler"` | no |
| <a name="input_lambda_alias_name"></a> [lambda\_alias\_name](#input\_lambda\_alias\_name) | Name of the alias pointing at the latest published orchestrator version. Durable functions must be invoked via a qualified ARN (version or alias); the alias gives callers a stable name while in-flight executions stay pinned to the version that started them. | `string` | `"prod"` | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | CloudWatch log retention for both functions. | `number` | `14` | no |
| <a name="input_max_revisions"></a> [max\_revisions](#input\_max\_revisions) | Max writer/editor revision loops before the draft goes to human approval regardless of score. | `number` | `2` | no |
| <a name="input_model_id"></a> [model\_id](#input\_model\_id) | Bedrock model or inference-profile ID used by every agent step. Model access must be granted in the deployment region. | `string` | `"us.anthropic.claude-haiku-4-5-20251001-v1:0"` | no |
| <a name="input_orchestrator_memory_mb"></a> [orchestrator\_memory\_mb](#input\_orchestrator\_memory\_mb) | Memory for the orchestrator Lambda. | `number` | `512` | no |
| <a name="input_orchestrator_reserved_concurrency"></a> [orchestrator\_reserved\_concurrency](#input\_orchestrator\_reserved\_concurrency) | Reserved concurrent executions for the orchestrator - a cost guardrail against runaway invocations. Set -1 for unreserved. | `number` | `5` | no |
| <a name="input_orchestrator_timeout_seconds"></a> [orchestrator\_timeout\_seconds](#input\_orchestrator\_timeout\_seconds) | Per-invocation timeout for the orchestrator Lambda (each replay slice, not the whole execution). | `number` | `90` | no |
| <a name="input_project_name"></a> [project\_name](#input\_project\_name) | Prefix used for all resource names. | `string` | `"durable-ai-agent"` | no |
| <a name="input_runtime"></a> [runtime](#input\_runtime) | Lambda runtime for both functions. Durable functions support python3.13/python3.14 (and Node.js/Java equivalents). | `string` | `"python3.13"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to all resources. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_api_endpoint"></a> [api\_endpoint](#output\_api\_endpoint) | Base URL for the HTTP API. |
| <a name="output_api_function_name"></a> [api\_function\_name](#output\_api\_function\_name) | Name of the API Lambda function. |
| <a name="output_executions_table"></a> [executions\_table](#output\_executions\_table) | DynamoDB table tracking pipeline run status. |
| <a name="output_orchestrator_function_name"></a> [orchestrator\_function\_name](#output\_orchestrator\_function\_name) | Name of the durable orchestrator function. |
| <a name="output_orchestrator_qualified_arn"></a> [orchestrator\_qualified\_arn](#output\_orchestrator\_qualified\_arn) | Qualified ARN (prod alias) of the durable orchestrator function - use this for invocations. |
| <a name="output_orchestrator_role_arn"></a> [orchestrator\_role\_arn](#output\_orchestrator\_role\_arn) | Execution role ARN of the orchestrator (for extending permissions). |
| <a name="output_posts_bucket"></a> [posts\_bucket](#output\_posts\_bucket) | S3 bucket that published drafts land in. |
<!-- END_TF_DOCS -->

## Authors

Maintained by [Amrut Pagidipally](https://github.com/amrutp24).

## License

Apache-2.0 — see [LICENSE](LICENSE).
