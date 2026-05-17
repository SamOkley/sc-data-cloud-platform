output "api_name" {
  description = "API Gateway name"
  value       = aws_apigatewayv2_api.api.name
}

output "api_endpoint" {
  description = "API Gateway invoke URL"
  value       = aws_apigatewayv2_stage.stage.invoke_url
}