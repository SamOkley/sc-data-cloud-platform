# =============================================================================
# NOTIFICATIONS MODULE - Smart City Data Platform
# Phase 2: Alerting – SNS + CloudWatch Alarms
# =============================================================================

# ── SNS Topic ─────────────────────────────────────────────────────────────────
resource "aws_sns_topic" "pipeline_alerts" {
  name              = "${var.project_name}-${var.environment}-pipeline-alerts"
  kms_master_key_id = "alias/aws/sns"

  tags = var.tags
}

resource "aws_sns_topic_policy" "pipeline_alerts" {
  arn = aws_sns_topic.pipeline_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudWatchPublish"
        Effect = "Allow"
        Principal = { Service = "cloudwatch.amazonaws.com" }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.pipeline_alerts.arn
      },
      {
        Sid    = "AllowEventBridgePublish"
        Effect = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.pipeline_alerts.arn
      }
    ]
  })
}

# ── Email subscriptions ───────────────────────────────────────────────────────
resource "aws_sns_topic_subscription" "email" {
  for_each  = toset(var.alert_email_addresses)
  topic_arn = aws_sns_topic.pipeline_alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

# ── SMS subscriptions ─────────────────────────────────────────────────────────
resource "aws_sns_topic_subscription" "sms" {
  for_each  = toset(var.alert_phone_numbers)
  topic_arn = aws_sns_topic.pipeline_alerts.arn
  protocol  = "sms"
  endpoint  = each.value
}

# ── CloudWatch Alarms ─────────────────────────────────────────────────────────

# Lambda ingestion errors
resource "aws_cloudwatch_metric_alarm" "lambda_ingestion_errors" {
  alarm_name          = "${var.project_name}-${var.environment}-lambda-ingestion-errors"
  alarm_description   = "Lambda ingestion function error rate too high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = var.lambda_error_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = var.lambda_ingestion_function_name
  }

  alarm_actions = [aws_sns_topic.pipeline_alerts.arn]
  ok_actions    = [aws_sns_topic.pipeline_alerts.arn]

  tags = var.tags
}

# Lambda processor errors
resource "aws_cloudwatch_metric_alarm" "lambda_processor_errors" {
  alarm_name          = "${var.project_name}-${var.environment}-lambda-processor-errors"
  alarm_description   = "Lambda processor function error rate too high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = var.lambda_error_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = var.lambda_processor_function_name
  }

  alarm_actions = [aws_sns_topic.pipeline_alerts.arn]
  ok_actions    = [aws_sns_topic.pipeline_alerts.arn]

  tags = var.tags
}

# Kinesis iterator age (consumer lag)
resource "aws_cloudwatch_metric_alarm" "kinesis_iterator_age" {
  alarm_name          = "${var.project_name}-${var.environment}-kinesis-iterator-age"
  alarm_description   = "Kinesis consumer is lagging – iterator age too high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "GetRecords.IteratorAgeMilliseconds"
  namespace           = "AWS/Kinesis"
  period              = 60
  extended_statistic  = "p99"
  threshold           = var.kinesis_iterator_age_threshold_ms
  treat_missing_data  = "notBreaching"

  dimensions = {
    StreamName = var.kinesis_stream_name
  }

  alarm_actions = [aws_sns_topic.pipeline_alerts.arn]

  tags = var.tags
}

# Glue ETL job failures (EventBridge rule → SNS)
resource "aws_cloudwatch_event_rule" "glue_job_failure" {
  name        = "${var.project_name}-${var.environment}-glue-job-failure"
  description = "Fires when any Glue ETL job transitions to FAILED state"

  event_pattern = jsonencode({
    source      = ["aws.glue"]
    detail-type = ["Glue Job State Change"]
    detail = {
      jobName = [var.glue_job_name]
      state   = ["FAILED", "TIMEOUT", "STOPPED"]
    }
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "glue_failure_sns" {
  rule      = aws_cloudwatch_event_rule.glue_job_failure.name
  target_id = "send-to-sns"
  arn       = aws_sns_topic.pipeline_alerts.arn

  input_transformer {
    input_paths = {
      jobName   = "$.detail.jobName"
      state     = "$.detail.state"
      startedOn = "$.detail.startedOn"
    }
    input_template = "\"ALERT: Glue job <jobName> entered state <state> (started: <startedOn>)\""
  }
}

# Pipeline stall – processor Lambda hasn't run in the expected window.
# (AWS/S3 has no per-minute "object uploaded" metric without paid request-metrics,
# so we proxy stall detection via the processor Lambda's invocation count.)
resource "aws_cloudwatch_metric_alarm" "s3_pipeline_stall" {
  alarm_name          = "${var.project_name}-${var.environment}-pipeline-stall"
  alarm_description   = "Processor Lambda has not been invoked in the expected window - pipeline is stalled"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Invocations"
  namespace           = "AWS/Lambda"
  period              = var.pipeline_stall_period_seconds
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "breaching"

  dimensions = {
    FunctionName = var.lambda_processor_function_name
  }

  alarm_actions = [aws_sns_topic.pipeline_alerts.arn]

  tags = var.tags
}

# API Gateway 5xx errors
resource "aws_cloudwatch_metric_alarm" "apigw_5xx" {
  alarm_name          = "${var.project_name}-${var.environment}-apigw-5xx"
  alarm_description   = "API Gateway 5xx error rate elevated"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period              = 300
  statistic           = "Sum"
  threshold           = var.apigw_5xx_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    ApiName = var.api_gateway_name
  }

  alarm_actions = [aws_sns_topic.pipeline_alerts.arn]
  ok_actions    = [aws_sns_topic.pipeline_alerts.arn]

  tags = var.tags
}
