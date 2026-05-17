variable "project_name"  { type = string }
variable "environment"   { type = string }
variable "datalake_bucket" { type = string }

variable "alert_email_addresses" {
  description = "List of email addresses to subscribe to pipeline alerts"
  type        = list(string)
  default     = []
}

variable "alert_phone_numbers" {
  description = "E.164 phone numbers for SMS alerts (e.g. +61412345678)"
  type        = list(string)
  default     = []
}

variable "lambda_ingestion_function_name" { type = string }
variable "lambda_processor_function_name" { type = string }
variable "kinesis_stream_name"            { type = string }
variable "glue_job_name"                  { type = string }
variable "api_gateway_name"               { type = string }

variable "lambda_error_threshold" {
  type    = number
  default = 5
}

variable "kinesis_iterator_age_threshold_ms" {
  description = "Max acceptable Kinesis iterator age in milliseconds"
  type        = number
  default     = 60000 # 60 seconds
}

variable "pipeline_stall_period_seconds" {
  description = "Period (seconds) with no S3 writes before a stall alarm fires"
  type        = number
  default     = 3600 # 1 hour
}

variable "apigw_5xx_threshold" {
  type    = number
  default = 10
}

variable "tags" {
  type    = map(string)
  default = {}
}
