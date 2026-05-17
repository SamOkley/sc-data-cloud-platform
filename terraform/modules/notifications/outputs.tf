output "sns_topic_arn" {
  value = aws_sns_topic.pipeline_alerts.arn
}

output "sns_topic_name" {
  value = aws_sns_topic.pipeline_alerts.name
}

output "alarm_names" {
  value = {
    lambda_ingestion  = aws_cloudwatch_metric_alarm.lambda_ingestion_errors.alarm_name
    lambda_processor  = aws_cloudwatch_metric_alarm.lambda_processor_errors.alarm_name
    kinesis_lag       = aws_cloudwatch_metric_alarm.kinesis_iterator_age.alarm_name
    s3_stall          = aws_cloudwatch_metric_alarm.s3_pipeline_stall.alarm_name
    apigw_5xx         = aws_cloudwatch_metric_alarm.apigw_5xx.alarm_name
  }
}
