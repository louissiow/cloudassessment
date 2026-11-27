variable "public_zone_id" {
  description = "Route 53 public hosted zone ID for t1dx.example."
  type        = string
}

variable "origin_record_name" {
  description = "CloudFront (t1dx-cf-edge) API origin hostname. Same API GW custom domain exists in both Regions."
  type        = string
  default     = "api-origin.t1dx.example"
}

variable "apigw_regional_domain" {
  description = "API Gateway regional custom-domain targets per Region (regional_domain_name / regional_zone_id of aws_api_gateway_domain_name)."
  type = map(object({
    domain_name = string
    zone_id     = string
  }))
  # keys: apse5, apse1
}

variable "aurora_engine_version" {
  description = "Aurora PostgreSQL version. Primary and secondary must run the same major + minor version for managed switchover/failover."
  type        = string
  default     = "16.8"
}

variable "aurora_instance_class" {
  type    = string
  default = "db.r7g.2xlarge"
}

variable "db_subnet_group" {
  description = "DB subnet group name per Region (private data subnets across 3 AZs)."
  type        = map(string)
}

variable "db_security_group_ids" {
  description = "Security groups per Region allowing only RDS Proxy / EKS pod SGs."
  type        = map(list(string))
}

variable "db_master_password" {
  description = "Initial master password, sourced from Secrets Manager (replicated) by the pipeline. Rotated after creation."
  type        = string
  sensitive   = true
}
