variable "project_name" {
  description = "Prefix used for all resource names."
  type        = string
  default     = "durable-ai-agent"
}

variable "orchestrator_package" {
  description = "Path to the pre-built zip for the durable orchestrator Lambda (must bundle aws-durable-execution-sdk-python)."
  type        = string
}

variable "api_package" {
  description = "Path to the pre-built zip for the API Lambda (must bundle a boto3 recent enough for SendDurableExecutionCallbackSuccess)."
  type        = string
}

variable "lambda_alias_name" {
  description = "Name of the alias pointing at the latest published orchestrator version. Durable functions must be invoked via a qualified ARN (version or alias); the alias gives callers a stable name while in-flight executions stay pinned to the version that started them."
  type        = string
  default     = "prod"
}

variable "handler" {
  description = "Lambda handler for both functions (module.function format matching your packaged code)."
  type        = string
  default     = "lambda_function.lambda_handler"
}

variable "api_memory_mb" {
  description = "Memory for the API Lambda."
  type        = number
  default     = 256
}

variable "api_timeout_seconds" {
  description = "Per-invocation timeout for the API Lambda."
  type        = number
  default     = 30
}

variable "runtime" {
  description = "Lambda runtime for both functions. Durable functions support python3.13/python3.14 (and Node.js/Java equivalents)."
  type        = string
  default     = "python3.13"
}

variable "model_id" {
  description = "Bedrock model or inference-profile ID used by every agent step. Model access must be granted in the deployment region."
  type        = string
  default     = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
}

variable "max_revisions" {
  description = "Max writer/editor revision loops before the draft goes to human approval regardless of score."
  type        = number
  default     = 2
}

variable "approval_score_threshold" {
  description = "Editor score (1-10) at or above which the draft is considered good enough."
  type        = number
  default     = 8
}

variable "callback_timeout_seconds" {
  description = "How long the orchestrator waits for human approval before giving up."
  type        = number
  default     = 86400
}

variable "durable_execution_timeout_seconds" {
  description = "Max total lifetime of one durable execution (steps + waits combined). Max 1 year."
  type        = number
  default     = 172800
}

variable "durable_retention_period_days" {
  description = "How long Lambda retains checkpoint/execution history after completion (1-90)."
  type        = number
  default     = 7
}

variable "orchestrator_memory_mb" {
  description = "Memory for the orchestrator Lambda."
  type        = number
  default     = 512
}

variable "orchestrator_timeout_seconds" {
  description = "Per-invocation timeout for the orchestrator Lambda (each replay slice, not the whole execution)."
  type        = number
  default     = 90
}

variable "orchestrator_reserved_concurrency" {
  description = "Reserved concurrent executions for the orchestrator - a cost guardrail against runaway invocations. Set -1 for unreserved."
  type        = number
  default     = 5
}

variable "api_reserved_concurrency" {
  description = "Reserved concurrent executions for the API Lambda. Set -1 for unreserved."
  type        = number
  default     = 10
}

variable "log_retention_days" {
  description = "CloudWatch log retention for both functions."
  type        = number
  default     = 14
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
