# =============================================================================
# ROOT MAIN.TF – Smart City Data Platform
# Phase 2 additions wired below Phase 1 modules
# =============================================================================

# ── (Phase 1 modules – already exist, shown for context) ─────────────────────

module "s3_datalake" {
  source = "./modules/s3_datalake"
}

module "iam" {
  source = "./modules/iam"

  project_name    = var.project_name
  datalake_bucket = module.s3_datalake.bucket_name
}

module "kinesis" {
  source       = "./modules/kinesis"
  project_name = var.project_name
  environment  = var.environment
  tags         = local.common_tags
}


module "lambda_ingestion" {
  source = "./modules/lambda_ingestion"

  role_arn    = module.iam.lambda_role_arn
  stream_name = module.kinesis.stream_name
}

module "api_gateway" {
  source = "./modules/api_gateway"

  lambda_invoke_arn = module.lambda_ingestion.lambda_arn
  lambda_name       = module.lambda_ingestion.lambda_name
  aws_region        = var.aws_region
}

module "lambda_processor" {
  source = "./modules/lambda_processor"

  role_arn    = module.iam.lambda_role_arn
  bucket_name = module.s3_datalake.bucket_name
  stream_arn  = module.kinesis.stream_arn
}

# ── Phase 2: Athena ───────────────────────────────────────────────────────────
module "athena" {
  source          = "./modules/athena"
  project_name    = var.project_name
  environment     = var.environment
  datalake_bucket = module.s3_datalake.bucket_name
  results_bucket  = module.s3_datalake.bucket_name
  tags            = local.common_tags
}

# ── Phase 2: Glue ETL ─────────────────────────────────────────────────────────
module "glue" {
  source             = "./modules/glue"
  project_name       = var.project_name
  environment        = var.environment
  datalake_bucket    = module.s3_datalake.bucket_name
  scripts_bucket     = module.s3_datalake.bucket_name
  glue_database_name = module.athena.database_name
  worker_type        = var.glue_worker_type
  number_of_workers  = var.glue_number_of_workers
  etl_schedule_cron  = var.glue_etl_schedule_cron
  tags               = local.common_tags
}


# ── Phase 2: Notifications ────────────────────────────────────────────────────
module "notifications" {
  source          = "./modules/notifications"
  project_name    = var.project_name
  environment     = var.environment
  datalake_bucket = module.s3_datalake.bucket_name

  alert_email_addresses = var.alert_email_addresses
  alert_phone_numbers   = var.alert_phone_numbers

  lambda_ingestion_function_name = module.lambda_ingestion.function_name
  lambda_processor_function_name = module.lambda_processor.function_name
  kinesis_stream_name            = module.kinesis.stream_name
  glue_job_name                  = module.glue.glue_job_name
  api_gateway_name               = module.api_gateway.api_name

  tags = local.common_tags
}

# ── Phase 2: Monitoring / Dashboard ──────────────────────────────────────────
module "monitoring" {
  source       = "./modules/monitoring"
  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region

  api_gateway_name               = module.api_gateway.api_name
  lambda_ingestion_function_name = module.lambda_ingestion.function_name
  lambda_processor_function_name = module.lambda_processor.function_name
  kinesis_stream_name            = module.kinesis.stream_name
  glue_job_name                  = module.glue.glue_job_name

  alarm_arns = [
    "arn:aws:cloudwatch:${var.aws_region}:${data.aws_caller_identity.current.account_id}:alarm:${module.notifications.alarm_names.lambda_ingestion}",
    "arn:aws:cloudwatch:${var.aws_region}:${data.aws_caller_identity.current.account_id}:alarm:${module.notifications.alarm_names.lambda_processor}",
    "arn:aws:cloudwatch:${var.aws_region}:${data.aws_caller_identity.current.account_id}:alarm:${module.notifications.alarm_names.kinesis_lag}",
    "arn:aws:cloudwatch:${var.aws_region}:${data.aws_caller_identity.current.account_id}:alarm:${module.notifications.alarm_names.s3_stall}",
    "arn:aws:cloudwatch:${var.aws_region}:${data.aws_caller_identity.current.account_id}:alarm:${module.notifications.alarm_names.apigw_5xx}",
  ]

  tags = local.common_tags
}

# ── Data sources ──────────────────────────────────────────────────────────────
data "aws_caller_identity" "current" {}

# ── Locals ────────────────────────────────────────────────────────────────────
locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Phase       = "2"
  }
}
