terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region # run in staging first (L1), production only for approved game days
  default_tags {
    tags = {
      service    = "t1dx"
      managed-by = "terraform"
      stack      = "game-day"
    }
  }
}

variable "region" {
  type    = string
  default = "ap-southeast-5"
}

variable "region_code" {
  type    = string
  default = "apse5"
}

variable "fis_role_arn" {
  description = "Least-privilege FIS role, scoped to resources tagged gameday=allowed."
  type        = string
}

variable "stop_alarm_arns" {
  description = "CloudWatch alarm ARNs that stop any experiment (CUJ composite burn alarms)."
  type        = list(string)
}

variable "aurora_cluster_arn" {
  description = "ARN of t1dx-aurora-<region> (staging copy for L1c)."
  type        = string
}

variable "provider_cidrs" {
  description = "Egress destination CIDRs of ext-payment-switch (staging stub) for latency injection."
  type        = string
}
