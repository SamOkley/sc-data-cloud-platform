output "glue_job_name" {
  value = aws_glue_job.smart_city_etl.name
}

output "glue_role_arn" {
  value = aws_iam_role.glue_role.arn
}

output "etl_trigger_name" {
  value = aws_glue_trigger.scheduled_etl.name
}
