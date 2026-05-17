


# ── Core ──────────────────────────────────────────────────────────────────────
variable "project_name" {
  description = "Project name used as a prefix for all resources"
  type        = string
  default     = "smart-city"
}

variable "environment" {
  description = "Deployment environment (dev | staging | prod)"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "ap-southeast-2"   # Sydney
}

# ── Phase 2: Glue ─────────────────────────────────────────────────────────────
variable "glue_worker_type" {
  description = "Glue worker type (Standard, cheapest ETL option for dev)"
  type        = string
  default     = "G.1X"
}

variable "glue_number_of_workers" {
  description = "Number of Glue workers"
  type        = number
  default     = 2
}

variable "glue_etl_schedule_cron" {
  description = "Cron expression for the ETL trigger (Glue syntax)"
  type        = string
  default     = "cron(0 * * * ? *)"  # every hour on the hour
}

# ── Phase 2: Notifications ────────────────────────────────────────────────────
variable "alert_email_addresses" {
  description = "Email addresses to receive pipeline alerts (confirm subscription in email)"
  type        = list(string)
  default     = []
  # example: ["ops-team@example.com", "on-call@example.com"]
}

variable "alert_phone_numbers" {
  description = "E.164 phone numbers for SMS alerts"
  type        = list(string)
  default     = []
  # example: ["+61412345678"]
}
