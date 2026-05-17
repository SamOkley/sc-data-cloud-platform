
output "lambda_arn" {
  value = aws_lambda_function.ingestion.arn
}

output "lambda_name" {
  value = aws_lambda_function.ingestion.function_name
}

output "function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.ingestion.function_name
}