output "workgroup_name" {
  description = "Athena workgroup name"
  value       = aws_athena_workgroup.smart_city.name
}

output "database_name" {
  description = "Glue catalog database name (used by Athena)"
  value       = aws_glue_catalog_database.smart_city.name
}

output "telemetry_raw_table" {
  description = "Glue table name for raw telemetry"
  value       = aws_glue_catalog_table.telemetry_raw.name
}

output "telemetry_processed_table" {
  description = "Glue table name for processed telemetry"
  value       = aws_glue_catalog_table.telemetry_processed.name
}

output "named_query_ids" {
  description = "Map of saved Athena query names to IDs"
  value = {
    device_summary    = aws_athena_named_query.device_summary.id
    district_heatmap  = aws_athena_named_query.district_heatmap.id
    anomaly_detection = aws_athena_named_query.anomaly_detection.id
    pipeline_health   = aws_athena_named_query.pipeline_health.id
  }
}
