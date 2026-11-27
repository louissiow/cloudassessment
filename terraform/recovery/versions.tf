terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

locals {
  default_tags = {
    service    = "t1dx"
    managed-by = "terraform"
    stack      = "recovery"
  }
}

provider "aws" {
  alias  = "apse5" # primary: Asia Pacific (Malaysia)
  region = "ap-southeast-5"
  default_tags { tags = local.default_tags }
}

provider "aws" {
  alias  = "apse1" # recovery: Asia Pacific (Singapore)
  region = "ap-southeast-1"
  default_tags { tags = local.default_tags }
}

# Route 53 ARC recovery control *configuration* API is served from us-west-2.
# Routing control *state* is read/changed through the cluster's 5 Regional data-plane endpoints.
provider "aws" {
  alias  = "usw2"
  region = "us-west-2"
  default_tags { tags = local.default_tags }
}
