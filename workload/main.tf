data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# One zone, named explicitly, so the set can never grow when AWS adds a zone; the
# lookup also fails early if the zone is missing or impaired.
data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "zone-name"
    values = [coalesce(var.availability_zone, "${var.region}a")]
  }
}

# The official Debian 12 AMI (owner: Debian). floci's catalog mirrors the
# same owner and name pattern, so this lookup is identical on both targets.
data "aws_ami" "debian" {
  most_recent = true
  owners      = ["136693071363"]

  filter {
    name   = "name"
    values = ["debian-12-${var.architecture}-*"]
  }

  filter {
    name   = "architecture"
    values = [var.architecture == "arm64" ? "arm64" : "x86_64"]
  }
}

locals {
  az             = data.aws_availability_zones.available.names[0]
  public_cidr    = cidrsubnet(var.vpc_cidr, 8, 0)
  private_cidr   = cidrsubnet(var.vpc_cidr, 8, 1)
  endpoint_cidr  = cidrsubnet(var.vpc_cidr, 12, 32) # a /28 right after the private /24
  account_id     = data.aws_caller_identity.current.account_id
  partition      = data.aws_partition.current.partition
  ssm_prefix     = "/${var.cluster_name}"
  instance_small = var.architecture == "arm64" ? "t4g.small" : "t3.small"
  instance_micro = var.architecture == "arm64" ? "t4g.micro" : "t3.micro"

  # KTHW lab 1 sizes. pod_subnet is lab 3's POD_SUBNET column; data_volume is
  # the dedicated containerd volume (spike 02).
  machines = {
    jumpbox = { ip = cidrhost(local.private_cidr, 4), type = local.instance_micro, pod_subnet = "", data_volume = false }
    server  = { ip = cidrhost(local.private_cidr, 10), type = local.instance_small, pod_subnet = "", data_volume = false }
    node-0  = { ip = cidrhost(local.private_cidr, 20), type = local.instance_small, pod_subnet = "10.200.0.0/24", data_volume = true }
    node-1  = { ip = cidrhost(local.private_cidr, 21), type = local.instance_small, pod_subnet = "10.200.1.0/24", data_volume = true }
  }
  cluster_members = { for k, v in local.machines : k => v if k != "jumpbox" }

  # Lab 3's machine database, one line per cluster member.
  machines_txt = join("", [for k in ["server", "node-0", "node-1"] :
    "${trimspace("${local.machines[k].ip} ${k}.kubernetes.local ${k} ${local.machines[k].pod_subnet}")}\n"
  ])
}
