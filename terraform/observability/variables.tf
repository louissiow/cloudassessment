variable "region" {
  description = "AWS Region for this deployment (ap-southeast-5 or ap-southeast-1)."
  type        = string
}

variable "region_code" {
  description = "Short Region code used in names: apse5 or apse1."
  type        = string
  validation {
    condition     = contains(["apse5", "apse1"], var.region_code)
    error_message = "region_code must be apse5 or apse1."
  }
}

variable "page_topic_arns" {
  description = "SNS topic per owner team for pages (t1dx-page-<team>), subscribed by the bank paging tool."
  type        = map(string)
}

variable "ticket_topic_arns" {
  description = "SNS topic per owner team for tickets (t1dx-ticket-<team>), subscribed by ITSM."
  type        = map(string)
}

variable "min_requests_short_window" {
  description = "Minimum valid requests in a window before burn-rate alerts can fire (low-traffic guard)."
  type        = number
  default     = 500
}

variable "canary_artifact_bucket" {
  description = "S3 bucket for Synthetics artefacts (lifecycle 30 days)."
  type        = string
}

variable "canary_execution_role_arn" {
  description = "IAM role for CloudWatch Synthetics canaries."
  type        = string
}

variable "canary_runtime_version" {
  description = "Synthetics Node.js runtime. Use the latest supported version at deploy time."
  type        = string
  default     = "syn-nodejs-puppeteer-9.1"
}

variable "public_api_base_url" {
  description = "Public API base URL through CloudFront (t1dx-cf-edge)."
  type        = string
  default     = "https://api.t1dx.example"
}
