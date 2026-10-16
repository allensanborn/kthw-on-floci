variable "region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name used in resource names, tags and SSM parameter paths."
  type        = string
  default     = "kthw"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,20}$", var.cluster_name))
    error_message = "cluster_name must be 2-21 lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "architecture" {
  description = "CPU architecture of the machines: arm64 or amd64 (KTHW supports both)."
  type        = string
  default     = "arm64"

  validation {
    condition     = contains(["arm64", "amd64"], var.architecture)
    error_message = "architecture must be arm64 or amd64."
  }
}

variable "vpc_cidr" {
  # Avoids KTHW's pod (10.200.0.0/16) and service (10.32.0.0/24) ranges, Docker's default
  # pools (172.17.0.0/12, 192.168.0.0/16) and floci's VPC fallback pool (10.240.0.0/12): on
  # floci the VPC becomes a Docker network, and a range already taken there is substituted.
  description = "VPC CIDR."
  type        = string
  default     = "10.100.0.0/16"
}

variable "flow_log_retention_days" {
  description = "CloudWatch retention for VPC flow logs (FedRAMP Moderate AU-11: keep at least 90 days online)."
  type        = number
  default     = 365
}
