output "api_endpoint" {
  description = "Base URL for the HTTP API."
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "orchestrator_function_name" {
  description = "Name of the durable orchestrator function."
  value       = aws_lambda_function.orchestrator.function_name
}

output "orchestrator_qualified_arn" {
  description = "Qualified ARN (prod alias) of the durable orchestrator function - use this for invocations."
  value       = aws_lambda_alias.orchestrator_prod.arn
}

output "api_function_name" {
  description = "Name of the API Lambda function."
  value       = aws_lambda_function.api.function_name
}

output "posts_bucket" {
  description = "S3 bucket that published drafts land in."
  value       = aws_s3_bucket.posts.bucket
}

output "executions_table" {
  description = "DynamoDB table tracking pipeline run status."
  value       = aws_dynamodb_table.executions.name
}

output "orchestrator_role_arn" {
  description = "Execution role ARN of the orchestrator (for extending permissions)."
  value       = aws_iam_role.orchestrator.arn
}
