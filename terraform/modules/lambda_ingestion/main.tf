resource "aws_lambda_function" "ingestion" {
  function_name = "telemetry-ingestion"

  role    = var.role_arn
  runtime = "python3.11"
  handler = "app.lambda_handler"

  filename = "${path.root}/../lambdas/ingestion_lambda/ingestion.zip"

  source_code_hash = filebase64sha256("${path.root}/../lambdas/ingestion_lambda/ingestion.zip")

  environment {
    variables = {
      STREAM_NAME = var.stream_name
    }
  }
}