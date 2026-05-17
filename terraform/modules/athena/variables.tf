variable "project_name" {
  description = "Project name prefix for all resources"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev / staging / prod)"
  type        = string
}

variable "datalake_bucket" {
  description = "S3 bucket name for the data lake"
  type        = string
}

variable "results_bucket" {
  description = "S3 bucket name for Athena query results"
  type        = string
}

variable "bytes_scanned_cutoff_per_query" {
  description = "Maximum bytes scanned per Athena query (cost guard-rail)"
  type        = number
  default     = 1073741824 # 1 GB
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
