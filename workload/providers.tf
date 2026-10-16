# Targets real AWS by default. On floci, AWS_ENDPOINT_URL (set by `mise run`
# tasks) redirects every service; nothing in this root changes.
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "kthw-on-floci"
      Cluster   = var.cluster_name
      ManagedBy = "terraform"
    }
  }
}
