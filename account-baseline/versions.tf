terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.69.1"
    }
  }

  backend "s3" {
    key          = "kthw/account-baseline.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "kthw-on-floci"
      ManagedBy = "terraform"
    }
  }
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "name_prefix" {
  type    = string
  default = "kthw"
}

variable "log_retention_days" {
  # OMB M-21-31, which FedRAMP's AU-11 follows: 12 months active and 18 months cold, 30
  # in all. 1096 days is 3 years and a value CloudWatch Logs accepts.
  description = "Audit log retention, in days, for S3 and CloudWatch Logs."
  type        = number
  default     = 1096
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
}
