# Security posture

This module runs Checkov and Trivy (tfsec's maintained successor) in CI with
**hard fail** — no soft-fail flag, no global suppressions. Every finding is
either fixed or carries a reasoned exception: inline `#checkov:skip` comments
at the resource, and [`.trivyignore`](.trivyignore) entries with comments,
all listed here for review. If your threat model disagrees with a decision,
the "If you need it" column tells you what to change downstream.

> Why Trivy and not tfsec itself: tfsec was archived into Trivy in 2024. Its
> final release predates the AWS provider's split S3 resources, so it reports
> encryption/versioning as missing even when they're configured — a scanner
> that can't see the controls can't attest to them.

## Controls implemented

| Control | Where |
| --- | --- |
| S3 server-side encryption (SSE-S3) | `aws_s3_bucket_server_side_encryption_configuration.posts` |
| S3 versioning | `aws_s3_bucket_versioning.posts` |
| S3 public access fully blocked | `aws_s3_bucket_public_access_block.posts` |
| DynamoDB point-in-time recovery | `aws_dynamodb_table.executions` |
| DynamoDB encryption at rest | AWS-owned key (always on) |
| Least-privilege IAM, scoped per resource | `main.tf` IAM section |
| Durable-callback grant scoped to one function's versions | `"${function_arn}:*"`, not `lambda:*` or `Resource: *` |
| CloudWatch log retention bounds | `log_retention_days` (validated against CW's allowed values) |
| Lambda concurrency guardrails | `*_reserved_concurrency` variables |
| Input validation on all constrained variables | 8 `validation` blocks in `variables.tf` |

## Accepted exceptions (inline `#checkov:skip`, reasoned)

| Check | Control | Why it's skipped here | If you need it |
| --- | --- | --- | --- |
| CKV_AWS_117 | Lambda in VPC | Functions call only regional AWS APIs (Bedrock, DynamoDB, S3); a VPC adds NAT cost and cold-start latency with no boundary gain | Fork and add `vpc_config`; nothing in the module assumes no-VPC |
| CKV_AWS_116 | Lambda DLQ | Durable executions retain complete failure state and history for `durable_retention_period_days` — richer than a DLQ message | Add an `aws_lambda_function_event_invoke_config` on the alias |
| CKV_AWS_50 | X-Ray tracing | Durable executions have checkpoint-level tracing in the Lambda console; X-Ray adds per-trace cost | Set `tracing_config` in a fork; consider it if you chain many services |
| CKV_AWS_173 | KMS-CMK for env vars | Env vars carry non-sensitive config (table/bucket names, model ID, tuning numbers) — verified, not assumed | Pass a `kms_key_arn`; do NOT put secrets in env vars either way |
| CKV_AWS_272 | Code signing | Packages are consumer-supplied pre-built zips; signing is a supply-chain decision that belongs in the consumer's build | Create a signing profile and `code_signing_config_arn` |
| CKV_AWS_119 | DynamoDB CMK | Table holds run status + callback IDs (opaque tokens usable only with IAM permission on the specific function) | Fork with `server_side_encryption` block |
| CKV_AWS_158 | Log group CMK | Logs contain step progress lines, no payload data; default SSE applies | Set `kms_key_id` on the log groups |
| CKV_AWS_18 / CKV_AWS_144 / CKV2_AWS_61 / CKV2_AWS_62 | S3 access logging / replication / lifecycle / notifications | Output bucket for published artifacts; posts are kept indefinitely by design | Standard S3 additions downstream |
| CKV_AWS_145 | S3 KMS (vs SSE-S3) | AES256 SSE is enabled; CMK adds key-management burden without a driver for public-by-intent content | Swap `sse_algorithm` to `aws:kms` |
| CKV_AWS_95 / CKV2_AWS_4 | API GW access logging | Lambda logs cover request tracing at this scale | Add a log group + `access_log_settings` on the stage |
| CKV_AWS_115 | Lambda reserved concurrency | It IS exposed (`*_reserved_concurrency`) — the skip exists because `-1` must be allowed for accounts whose total concurrency limit is ≤ 50 (AWS requires 50 unreserved) | Set the variables on accounts with raised limits |
| CKV_AWS_309 | API route authorization | Exposed as `api_authorization_type`; `NONE` default keeps the demo curl-able | Set `api_authorization_type = "AWS_IAM"` for SigV4-signed requests |
| CKV_AWS_76 | API GW access logging | Same reasoning as CKV_AWS_95 | Add `access_log_settings` on the stage |
| CKV_AWS_338 | Log retention ≥ 1 year | Retention is the `log_retention_days` variable; 14-day default is a cost choice for step-progress logs | Set `log_retention_days = 365`+ |

## Data classification

| Store | Data | Sensitivity |
| --- | --- | --- |
| DynamoDB | run status, topic, draft text, callback ID | Low; callback IDs are unusable without IAM on the specific function |
| S3 | approved, published posts | Public-by-intent |
| CloudWatch | step progress logs | Low; no payloads |
| Lambda env | resource names + tuning | Config, not secrets |

**Deliberate invariant: this module needs no secrets.** No API keys, no
passwords, no tokens — Bedrock, DynamoDB, S3, and the durable callback API are
all reached with the execution role. If a fork adds third-party calls, use
Secrets Manager, never env vars.
