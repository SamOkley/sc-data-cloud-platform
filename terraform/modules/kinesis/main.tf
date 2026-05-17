resource "aws_kinesis_stream" "telemetry_stream" {
  name             = "${var.project_name}-${var.environment}-telemetry-stream"
  shard_count      = 1
  retention_period = 24

  stream_mode_details {
    stream_mode = "PROVISIONED"
  }

  tags = var.tags
}

