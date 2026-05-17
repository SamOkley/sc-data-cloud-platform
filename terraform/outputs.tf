# ── Phase 1 outputs ────────────────────────────────────────────────────────
output "api_gateway_endpoint" {
  description = "Public endpoint for telemetry ingestion"
  value = module.api_gateway.api_endpoint
}


output "kinesis_stream_name" {
  description = "Kinesis Data Stream name"
  value       = module.kinesis.stream_name
}

output "datalake_bucket" {
  description = "S3 data lake bucket name"
  value       = module.s3_datalake.bucket_name
}

# ── Phase 2 outputs ────────────────────────────────────────────────────────
output "athena_workgroup" {
  description = "Athena workgroup for analytics queries"
  value       = module.athena.workgroup_name
}

output "glue_database" {
  description = "Glue / Athena catalog database"
  value       = module.athena.database_name
}

output "glue_etl_job" {
  description = "Glue ETL job name"
  value       = module.glue.glue_job_name
}

output "alerts_sns_topic_arn" {
  description = "SNS topic ARN for pipeline alerts"
  value       = module.notifications.sns_topic_arn
}

output "cloudwatch_dashboard_url" {
  description = "CloudWatch dashboard URL"
  value       = module.monitoring.dashboard_url
}
