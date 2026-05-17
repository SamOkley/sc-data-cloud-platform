output "lambda_arn" {
  value = aws_lambda_function.processor.arn
}

output "function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.processor.function_name
}