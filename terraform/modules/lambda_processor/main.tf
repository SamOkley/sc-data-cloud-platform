resource "aws_lambda_function" "processor" {
  function_name = "kinesis-to-s3-processor"

  role    = var.role_arn
  runtime = "python3.11"
  handler = "app.lambda_handler"

  filename         = "${path.root}/../lambdas/processor_lambda/processor.zip"
  source_code_hash = filebase64sha256("${path.root}/../lambdas/processor_lambda/processor.zip")

  environment {
    variables = {
      DATA_LAKE_BUCKET = var.bucket_name
    }
  }
}

resource "aws_lambda_event_source_mapping" "kinesis_trigger" {
  event_source_arn  = var.stream_arn
  function_name     = aws_lambda_function.processor.arn
  starting_position = "LATEST"
  batch_size        = 10
}