output "stream_name" {
  value = aws_kinesis_stream.telemetry_stream.name
}

output "stream_arn" {
  value = aws_kinesis_stream.telemetry_stream.arn
}

