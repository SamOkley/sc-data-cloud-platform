# =============================================================================
# GLUE ETL MODULE - Smart City Data Platform
# Phase 2: ETL & Data Transformation
# =============================================================================

# ── S3 location for Glue job scripts ─────────────────────────────────────────
resource "aws_s3_object" "glue_etl_script" {
  bucket  = var.scripts_bucket
  key     = "glue-scripts/smart_city_etl.py"
  content = file("${path.module}/scripts/smart_city_etl.py")
  etag    = filemd5("${path.module}/scripts/smart_city_etl.py")

  tags = var.tags
}

# ── IAM role for Glue ─────────────────────────────────────────────────────────
resource "aws_iam_role" "glue_role" {
  name = "${var.project_name}-${var.environment}-glue-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "glue.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "glue_s3_access" {
  name = "glue-s3-access"
  role = aws_iam_role.glue_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.datalake_bucket}",
          "arn:aws:s3:::${var.datalake_bucket}/*",
          "arn:aws:s3:::${var.scripts_bucket}",
          "arn:aws:s3:::${var.scripts_bucket}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "glue:GetDatabase", "glue:GetTable", "glue:GetPartitions",
          "glue:CreatePartition", "glue:BatchCreatePartition",
          "glue:UpdatePartition", "glue:DeletePartition"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:/aws-glue/*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
}

# ── Glue Job ──────────────────────────────────────────────────────────────────
resource "aws_glue_job" "smart_city_etl" {
  name         = "${var.project_name}-${var.environment}-etl"
  role_arn     = aws_iam_role.glue_role.arn
  glue_version = "4.0"
  worker_type  = var.worker_type
  number_of_workers = var.number_of_workers

  command {
    name            = "glueetl"
    script_location = "s3://${var.scripts_bucket}/glue-scripts/smart_city_etl.py"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--job-bookmark-option"              = "job-bookmark-enable"
    "--enable-metrics"                   = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-spark-ui"                  = "true"
    "--spark-event-logs-path"            = "s3://${var.scripts_bucket}/spark-logs/"
    "--TempDir"                          = "s3://${var.scripts_bucket}/temp/"
    "--SOURCE_BUCKET"                    = var.datalake_bucket
    "--TARGET_BUCKET"                    = var.datalake_bucket
    "--DATABASE_NAME"                    = var.glue_database_name
    "--SOURCE_TABLE"                     = "telemetry_raw"
    "--TARGET_TABLE"                     = "telemetry_processed"
    "--ENVIRONMENT"                      = var.environment
  }

  execution_property {
    max_concurrent_runs = 1
  }

  timeout = var.job_timeout_minutes

  tags = var.tags
}

# ── Glue Trigger (scheduled) ──────────────────────────────────────────────────
resource "aws_glue_trigger" "scheduled_etl" {
  name     = "${var.project_name}-${var.environment}-etl-schedule"
  type     = "SCHEDULED"
  schedule = var.etl_schedule_cron # e.g. "cron(0 * * * ? *)" = hourly

  actions {
    job_name = aws_glue_job.smart_city_etl.name
  }

  tags = var.tags
}

