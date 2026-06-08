# =============================================================================
# Multi-Cloud APIM Gateway — AWS Terraform — Lambda (worldcup)
# =============================================================================

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.prefix}-worldcup"
  retention_in_days = 7 # keep storage well under the 5 GB perpetual free tier
}

resource "aws_lambda_function" "worldcup" {
  function_name = "${local.prefix}-worldcup"
  description   = "Mocked World Cup 2026 API + Swagger UI; secured by API Gateway JWT authorizer."

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  runtime = var.lambda_runtime
  handler = "index.handler"
  role    = aws_iam_role.lambda_exec.arn

  memory_size = var.lambda_memory_mb
  timeout     = var.lambda_timeout_seconds

  environment {
    variables = {
      ENVIRONMENT = var.environment_name
      WORKLOAD    = var.workload_name
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_logs,
    aws_cloudwatch_log_group.lambda
  ]
}

# Allow API Gateway HTTP API to invoke the Lambda
resource "aws_lambda_permission" "apigw_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.worldcup.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}
