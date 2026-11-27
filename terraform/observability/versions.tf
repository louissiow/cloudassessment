terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# Deploy this stack once per Region: ap-southeast-5 (primary) and ap-southeast-1 (recovery).
provider "aws" {
  region = var.region
  default_tags {
    tags = {
      service    = "t1dx"
      managed-by = "terraform"
      stack      = "observability"
    }
  }
}
