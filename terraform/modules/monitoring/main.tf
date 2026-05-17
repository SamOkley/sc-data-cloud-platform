# =============================================================================
# MONITORING MODULE - Smart City Data Platform
# Phase 2: CloudWatch Dashboard + Custom Metrics
# =============================================================================

locals {
  dashboard_name = "${var.project_name}-${var.environment}-pipeline"
}

resource "aws_cloudwatch_dashboard" "pipeline" {
  dashboard_name = local.dashboard_name

  dashboard_body = jsonencode({
    widgets = [

      # ── Row 1: API Gateway ──────────────────────────────────────────────────
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 1
        properties = { markdown = "## 🌐 API Gateway – Ingestion Layer" }
      },
      {
        type   = "metric"
        x      = 0
        y      = 1
        width  = 8
        height = 6
        properties = {
          title   = "API Requests (Count)"
          region  = var.aws_region
          period  = 300
          stat    = "Sum"
          view    = "timeSeries"
          metrics = [[
            "AWS/ApiGateway", "Count",
            "ApiName", var.api_gateway_name
          ]]
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 1
        width  = 8
        height = 6
        properties = {
          title   = "API Latency (p99 ms)"
          region  = var.aws_region
          period  = 300
          stat    = "p99"
          view    = "timeSeries"
          metrics = [[
            "AWS/ApiGateway", "Latency",
            "ApiName", var.api_gateway_name
          ]]
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 1
        width  = 8
        height = 6
        properties = {
          title  = "API 4xx / 5xx Errors"
          region = var.aws_region
          period = 300
          stat   = "Sum"
          view   = "timeSeries"
          metrics = [
            ["AWS/ApiGateway", "4XXError", "ApiName", var.api_gateway_name, { label = "4xx", color = "#FF9900" }],
            ["AWS/ApiGateway", "5XXError", "ApiName", var.api_gateway_name, { label = "5xx", color = "#D62728" }]
          ]
        }
      },

      # ── Row 2: Lambda ────────────────────────────────────────────────────────
      {
        type   = "text"
        x      = 0
        y      = 7
        width  = 24
        height = 1
        properties = { markdown = "## ⚡ Lambda – Processing Functions" }
      },
      {
        type   = "metric"
        x      = 0
        y      = 8
        width  = 8
        height = 6
        properties = {
          title  = "Lambda Invocations"
          region = var.aws_region
          period = 300
          stat   = "Sum"
          view   = "timeSeries"
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", var.lambda_ingestion_function_name, { label = "Ingestion" }],
            ["AWS/Lambda", "Invocations", "FunctionName", var.lambda_processor_function_name, { label = "Processor" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 8
        width  = 8
        height = 6
        properties = {
          title  = "Lambda Errors"
          region = var.aws_region
          period = 300
          stat   = "Sum"
          view   = "timeSeries"
          metrics = [
            ["AWS/Lambda", "Errors", "FunctionName", var.lambda_ingestion_function_name, { label = "Ingestion Errors", color = "#D62728" }],
            ["AWS/Lambda", "Errors", "FunctionName", var.lambda_processor_function_name, { label = "Processor Errors", color = "#FF9900" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 8
        width  = 8
        height = 6
        properties = {
          title  = "Lambda Duration (p99 ms)"
          region = var.aws_region
          period = 300
          stat   = "p99"
          view   = "timeSeries"
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", var.lambda_ingestion_function_name, { label = "Ingestion" }],
            ["AWS/Lambda", "Duration", "FunctionName", var.lambda_processor_function_name, { label = "Processor" }]
          ]
        }
      },

      # ── Row 3: Kinesis ───────────────────────────────────────────────────────
      {
        type   = "text"
        x      = 0
        y      = 14
        width  = 24
        height = 1
        properties = { markdown = "## 🌊 Kinesis – Stream Buffering" }
      },
      {
        type   = "metric"
        x      = 0
        y      = 15
        width  = 8
        height = 6
        properties = {
          title   = "Kinesis Incoming Records"
          region  = var.aws_region
          period  = 60
          stat    = "Sum"
          view    = "timeSeries"
          metrics = [["AWS/Kinesis", "IncomingRecords", "StreamName", var.kinesis_stream_name]]
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 15
        width  = 8
        height = 6
        properties = {
          title   = "Iterator Age (p99 ms)"
          region  = var.aws_region
          period  = 60
          stat    = "p99"
          view    = "timeSeries"
          metrics = [["AWS/Kinesis", "GetRecords.IteratorAgeMilliseconds", "StreamName", var.kinesis_stream_name]]
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 15
        width  = 8
        height = 6
        properties = {
          title  = "Kinesis Read / Write Throttles"
          region = var.aws_region
          period = 60
          stat   = "Sum"
          view   = "timeSeries"
          metrics = [
            ["AWS/Kinesis", "ReadProvisionedThroughputExceeded", "StreamName", var.kinesis_stream_name, { color = "#D62728" }],
            ["AWS/Kinesis", "WriteProvisionedThroughputExceeded", "StreamName", var.kinesis_stream_name, { color = "#FF9900" }]
          ]
        }
      },

      # ── Row 4: Glue ──────────────────────────────────────────────────────────
      {
        type   = "text"
        x      = 0
        y      = 21
        width  = 24
        height = 1
        properties = { markdown = "## 🔧 Glue ETL – Transformation Layer" }
      },
      {
        type   = "metric"
        x      = 0
        y      = 22
        width  = 12
        height = 6
        properties = {
          title  = "Glue ETL – Bytes Read / Written"
          region = var.aws_region
          period = 300
          stat   = "Sum"
          view   = "timeSeries"
          metrics = [
            ["Glue", "glue.ALL.s3.filesystem.read_bytes", "JobName", var.glue_job_name, "JobRunId", "ALL", { label = "Read bytes" }],
            ["Glue", "glue.ALL.s3.filesystem.write_bytes", "JobName", var.glue_job_name, "JobRunId", "ALL", { label = "Written bytes" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 22
        width  = 12
        height = 6
        properties = {
          title   = "Glue ETL – Records Written"
          region  = var.aws_region
          period  = 300
          stat    = "Sum"
          view    = "timeSeries"
          metrics = [[
            "Glue", "glue.ALL.recordsRead",
            "JobName", var.glue_job_name, "JobRunId", "ALL"
          ]]
        }
      },

      # ── Row 5: Alarm summary ─────────────────────────────────────────────────
      {
        type   = "text"
        x      = 0
        y      = 28
        width  = 24
        height = 1
        properties = { markdown = "## 🚨 Alarm Status" }
      },
      {
        type   = "alarm"
        x      = 0
        y      = 29
        width  = 24
        height = 6
        properties = {
          title  = "Pipeline Health – All Alarms"
          alarms = var.alarm_arns
        }
      }
    ]
  })
}

# ── Log Metric Filters ────────────────────────────────────────────────────────

# Count ERROR log entries from Lambda functions
resource "aws_cloudwatch_log_metric_filter" "lambda_errors" {
  for_each = {
    ingestion = "/aws/lambda/${var.lambda_ingestion_function_name}"
    processor = "/aws/lambda/${var.lambda_processor_function_name}"
  }

  name           = "${var.project_name}-${var.environment}-${each.key}-error-count"
  log_group_name = each.value
  pattern        = "ERROR"

  metric_transformation {
    name          = "${each.key}ErrorCount"
    namespace     = "SmartCity/Pipeline"
    value         = "1"
    default_value = "0"
    unit          = "Count"
  }
}

# Count records successfully written to S3
resource "aws_cloudwatch_log_metric_filter" "records_written" {
  name           = "${var.project_name}-${var.environment}-records-written"
  log_group_name = "/aws/lambda/${var.lambda_processor_function_name}"
  pattern        = "\"records written\""

  metric_transformation {
    name          = "RecordsWritten"
    namespace     = "SmartCity/Pipeline"
    value         = "1"
    default_value = "0"
    unit          = "Count"
  }
}
