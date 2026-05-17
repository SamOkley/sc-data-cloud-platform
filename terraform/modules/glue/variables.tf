variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "datalake_bucket" {
  description = "S3 bucket for data lake (raw + processed)"
  type        = string
}

variable "scripts_bucket" {
  description = "S3 bucket for Glue scripts and temp files"
  type        = string
}

variable "glue_database_name" {
  description = "Glue catalog database name"
  type        = string
}

variable "worker_type" {
  description = "Glue worker type: G.1X | G.2X |G.025X"
  type        = string
  default     = "G.1X"
}

variable "number_of_workers" {
  description = "Number of Glue workers"
  type        = number
  default     = 2
}

variable "job_timeout_minutes" {
  description = "Glue job timeout in minutes"
  type        = number
  default     = 60
}

variable "etl_schedule_cron" {
  description = "Cron expression for the ETL schedule (Glue format)"
  type        = string
  default     = "cron(0 * * * ? *)" # every hour on the hour
}

variable "tags" {
  type    = map(string)
  default = {}
}