terraform {
  # 1.10+ for S3 native state locking (use_lockfile).
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.69.1"
    }
  }

  # Partial config: `terraform init -backend-config=../backends/<target>.s3.tfbackend`.
  backend "s3" {
    key          = "kthw/workload.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
