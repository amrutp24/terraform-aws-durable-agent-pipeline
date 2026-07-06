data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  region = data.aws_region.current.region
}

# --- State stores --------------------------------------------------------------

#checkov:skip=CKV_AWS_119:AWS-owned key encryption at rest is sufficient for run-status metadata
resource "aws_dynamodb_table" "executions" {
  name         = "${var.project_name}-executions"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "execution_id"
  tags         = var.tags

  attribute {
    name = "execution_id"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

#checkov:skip=CKV_AWS_18:Access logging needs a second bucket; out of scope for this pipeline's output bucket
#checkov:skip=CKV_AWS_144:Cross-region replication is left to consumers with DR requirements
#checkov:skip=CKV_AWS_145:SSE-S3 (AES256) is enabled below; a customer-managed KMS key is a consumer decision
#checkov:skip=CKV2_AWS_61:Published posts are kept indefinitely by design; no lifecycle rules
#checkov:skip=CKV2_AWS_62:No downstream consumers need bucket event notifications
resource "aws_s3_bucket" "posts" {
  bucket        = "${var.project_name}-posts-${random_id.bucket_suffix.hex}"
  force_destroy = true
  tags          = var.tags
}

resource "aws_s3_bucket_server_side_encryption_configuration" "posts" {
  bucket = aws_s3_bucket.posts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "posts" {
  bucket = aws_s3_bucket.posts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "posts" {
  bucket                  = aws_s3_bucket.posts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- IAM -----------------------------------------------------------------------

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "orchestrator" {
  name               = "${var.project_name}-orchestrator-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "orchestrator_basic" {
  role       = aws_iam_role.orchestrator.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Grants lambda:CheckpointDurableExecution and lambda:GetDurableExecutionState -
# required for any durable function's execution role.
resource "aws_iam_role_policy_attachment" "orchestrator_durable" {
  role       = aws_iam_role.orchestrator.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicDurableExecutionRolePolicy"
}

resource "aws_iam_role_policy" "orchestrator_inline" {
  name = "${var.project_name}-orchestrator-inline"
  role = aws_iam_role.orchestrator.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Cross-region inference profiles route to foundation models in
        # multiple regions, so both the profile ARN and the underlying
        # per-region model ARNs need to be permitted.
        Effect = "Allow"
        Action = ["bedrock:InvokeModel"]
        Resource = [
          "arn:aws:bedrock:${local.region}:${data.aws_caller_identity.current.account_id}:inference-profile/*",
          "arn:aws:bedrock:*::foundation-model/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem"]
        Resource = aws_dynamodb_table.executions.arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.posts.arn}/*"
      }
    ]
  })
}

resource "aws_iam_role" "api" {
  name               = "${var.project_name}-api-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "api_basic" {
  role       = aws_iam_role.api.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "api_inline" {
  name = "${var.project_name}-api-inline"
  role = aws_iam_role.api.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem"]
        Resource = aws_dynamodb_table.executions.arn
      },
      {
        Effect = "Allow"
        Action = ["lambda:InvokeFunction"]
        Resource = [
          aws_lambda_function.orchestrator.arn,
          aws_lambda_alias.orchestrator_prod.arn
        ]
      },
      {
        # Callback ARNs are sub-resources of the *versioned* function ARN:
        #   ...function:name:<version>/durable-execution/<execution-id>/<callback-id>
        # so the bare function/alias ARNs don't match - a trailing wildcard is
        # required.
        Effect = "Allow"
        Action = [
          "lambda:SendDurableExecutionCallbackSuccess",
          "lambda:SendDurableExecutionCallbackFailure"
        ]
        Resource = "${aws_lambda_function.orchestrator.arn}:*"
      }
    ]
  })
}

# --- Lambda functions -----------------------------------------------------------

#checkov:skip=CKV_AWS_158:Default CloudWatch SSE is sufficient; logs contain no sensitive payloads
resource "aws_cloudwatch_log_group" "orchestrator" {
  name              = "/aws/lambda/${var.project_name}-orchestrator"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

#checkov:skip=CKV_AWS_50:X-Ray adds cost; durable executions have their own checkpoint-level tracing in the Lambda console
#checkov:skip=CKV_AWS_115:Reserved concurrency is exposed as a variable; -1 supports accounts with total limit <= 50
#checkov:skip=CKV_AWS_116:No DLQ - durable executions retain full failure state and history for durable_retention_period_days
#checkov:skip=CKV_AWS_117:No VPC by design - the function only calls regional AWS APIs (Bedrock, DynamoDB, S3)
#checkov:skip=CKV_AWS_173:Env vars hold non-sensitive config only (table/bucket names, model id, tuning numbers)
#checkov:skip=CKV_AWS_272:Code signing is a consumer supply-chain decision; packages are passed in pre-built
resource "aws_lambda_function" "orchestrator" {
  function_name = "${var.project_name}-orchestrator"
  role          = aws_iam_role.orchestrator.arn
  handler       = var.handler
  runtime       = var.runtime
  timeout       = var.orchestrator_timeout_seconds
  memory_size   = var.orchestrator_memory_mb
  tags          = var.tags

  filename         = var.orchestrator_package
  source_code_hash = filebase64sha256(var.orchestrator_package)

  reserved_concurrent_executions = var.orchestrator_reserved_concurrency

  # Durable functions require a published version/alias - see aws_lambda_alias
  # below. publish = true pins a new version every apply.
  publish = true

  durable_config {
    execution_timeout = var.durable_execution_timeout_seconds
    retention_period  = var.durable_retention_period_days
  }

  environment {
    variables = {
      TABLE_NAME               = aws_dynamodb_table.executions.name
      BUCKET_NAME              = aws_s3_bucket.posts.bucket
      MODEL_ID                 = var.model_id
      MAX_REVISIONS            = var.max_revisions
      APPROVAL_SCORE_THRESHOLD = var.approval_score_threshold
      CALLBACK_TIMEOUT_SECONDS = var.callback_timeout_seconds
    }
  }

  depends_on = [aws_cloudwatch_log_group.orchestrator]
}

# Durable functions can only be invoked through a qualified ARN (version or
# alias). Callers use this alias rather than $LATEST so in-flight executions
# keep replaying against the code version that started them.
resource "aws_lambda_alias" "orchestrator_prod" {
  name             = var.lambda_alias_name
  function_name    = aws_lambda_function.orchestrator.function_name
  function_version = aws_lambda_function.orchestrator.version
}

#checkov:skip=CKV_AWS_158:Default CloudWatch SSE is sufficient; logs contain no sensitive payloads
resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/lambda/${var.project_name}-api"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

#checkov:skip=CKV_AWS_50:X-Ray adds cost; durable executions have their own checkpoint-level tracing in the Lambda console
#checkov:skip=CKV_AWS_115:Reserved concurrency is exposed as a variable; -1 supports accounts with total limit <= 50
#checkov:skip=CKV_AWS_116:No DLQ - durable executions retain full failure state and history for durable_retention_period_days
#checkov:skip=CKV_AWS_117:No VPC by design - the function only calls regional AWS APIs (Bedrock, DynamoDB, S3)
#checkov:skip=CKV_AWS_173:Env vars hold non-sensitive config only (table/bucket names, model id, tuning numbers)
#checkov:skip=CKV_AWS_272:Code signing is a consumer supply-chain decision; packages are passed in pre-built
resource "aws_lambda_function" "api" {
  function_name = "${var.project_name}-api"
  role          = aws_iam_role.api.arn
  handler       = var.handler
  runtime       = var.runtime
  timeout       = var.api_timeout_seconds
  memory_size   = var.api_memory_mb
  tags          = var.tags

  filename         = var.api_package
  source_code_hash = filebase64sha256(var.api_package)

  reserved_concurrent_executions = var.api_reserved_concurrency

  environment {
    variables = {
      TABLE_NAME                 = aws_dynamodb_table.executions.name
      ORCHESTRATOR_QUALIFIED_ARN = aws_lambda_alias.orchestrator_prod.arn
    }
  }

  depends_on = [aws_cloudwatch_log_group.api]
}

# --- API Gateway ------------------------------------------------------------------

resource "aws_apigatewayv2_api" "http_api" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"
  tags          = var.tags
}

resource "aws_apigatewayv2_integration" "api" {
  api_id                 = aws_apigatewayv2_api.http_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "start" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "POST /posts"
  target    = "integrations/${aws_apigatewayv2_integration.api.id}"
}

resource "aws_apigatewayv2_route" "status" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "GET /posts/{id}"
  target    = "integrations/${aws_apigatewayv2_integration.api.id}"
}

resource "aws_apigatewayv2_route" "approve" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "POST /posts/{id}/approve"
  target    = "integrations/${aws_apigatewayv2_integration.api.id}"
}

#checkov:skip=CKV_AWS_95:Access logging needs a log group + format contract; Lambda logs cover request tracing here
#checkov:skip=CKV2_AWS_4:Same as CKV_AWS_95 - deliberate omission for this demo-scale API
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true
  tags        = var.tags
}

resource "aws_lambda_permission" "apigw_invoke_api" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}
