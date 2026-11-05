terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Remote state: encrypted S3 bucket with native lockfile.
  # Supply bucket/key/region with `terraform init -backend-config=...`.
  backend "s3" {
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "hardened-k8s-platform"
      ManagedBy = "terraform"
    }
  }
}
