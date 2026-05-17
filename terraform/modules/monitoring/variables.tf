variable "project_name"  { type = string }
variable "environment"   { type = string }
variable "api_gateway_name"               { type = string }
variable "lambda_ingestion_function_name" { type = string }
variable "lambda_processor_function_name" { type = string }
variable "kinesis_stream_name"            { type = string }
variable "glue_job_name"                  { type = string }

variable "alarm_arns" {
  description = "List of CloudWatch alarm ARNs to display on the dashboard"
  type        = list(string)
  default     = []
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

