variable "project_name" {
  type        = string
  description = "Project name for IAM resource naming"
}

variable "datalake_bucket" {
  type        = string
  description = "S3 data lake bucket name the Lambda role is allowed to write to"
}