variable "project_name" {
  description = "Prefix used for all resource names."
  type        = string
  default     = "durable-ai-agent"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,40}$", var.project_name))
    error_message = "project_name must be lowercase kebab-case, 2-41 chars, starting with a letter (it prefixes S3/IAM/Lambda names)."
  }
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

  validation {
    condition     = contains(["python3.13", "python3.14", "nodejs22.x", "nodejs24.x", "java17", "java21", "java25"], var.runtime)
    error_message = "runtime must be one of the managed runtimes that support durable functions: python3.13, python3.14, nodejs22.x, nodejs24.x, java17, java21, java25."
  }
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

  validation {
    condition     = var.max_revisions >= 0 && var.max_revisions <= 10
    error_message = "max_revisions must be between 0 and 10 - every revision is two extra Bedrock calls."
  }
}

variable "approval_score_threshold" {
  description = "Editor score (1-10) at or above which the draft is considered good enough."
  type        = number
  default     = 8

  validation {
    condition     = var.approval_score_threshold >= 1 && var.approval_score_threshold <= 10
    error_message = "approval_score_threshold must be between 1 and 10 (the editor agent scores on that scale)."
  }
}

variable "callback_timeout_seconds" {
  description = "How long the orchestrator waits for human approval before giving up."
  type        = number
  default     = 86400

  validation {
    condition     = var.callback_timeout_seconds >= 60 && var.callback_timeout_seconds <= 31622400
    error_message = "callback_timeout_seconds must be between 60 and 31622400 seconds, and no larger than durable_execution_timeout_seconds."
  }
}

variable "durable_execution_timeout_seconds" {
  description = "Max total lifetime of one durable execution (steps + waits combined). Max 1 year."
  type        = number
  default     = 172800

  validation {
    condition     = var.durable_execution_timeout_seconds >= 60 && var.durable_execution_timeout_seconds <= 31622400
    error_message = "durable_execution_timeout_seconds must be between 60 (1 min) and 31622400 (366 days), the limits Lambda enforces."
  }
}

variable "durable_retention_period_days" {
  description = "How long Lambda retains checkpoint/execution history after completion (1-90)."
  type        = number
  default     = 7

  validation {
    condition     = var.durable_retention_period_days >= 1 && var.durable_retention_period_days <= 90
    error_message = "durable_retention_period_days must be between 1 and 90, the range Lambda supports."
  }
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

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be one of the retention values CloudWatch Logs supports."
  }
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}

variable "api_authorization_type" {
  description = "Authorization type for the HTTP API routes. NONE keeps the demo self-contained; AWS_IAM requires SigV4-signed requests."
  type        = string
  default     = "NONE"

  validation {
    condition     = contains(["NONE", "AWS_IAM"], var.api_authorization_type)
    error_message = "api_authorization_type must be NONE or AWS_IAM."
  }
}
