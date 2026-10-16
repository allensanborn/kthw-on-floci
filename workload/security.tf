# Tiered security groups (SC-7). Humans reach only the jumpbox, and only
# through the EC2 Instance Connect Endpoint; the cluster accepts SSH, the API
# and NodePorts only from the jumpbox.

resource "aws_security_group" "eice" {
  name        = "${var.cluster_name}-eice"
  description = "EC2 Instance Connect Endpoint: SSH out to the jumpbox only"
  vpc_id      = aws_vpc.this.id
}

resource "aws_security_group" "jumpbox" {
  name        = "${var.cluster_name}-jumpbox"
  description = "KTHW jumpbox"
  vpc_id      = aws_vpc.this.id
}

resource "aws_security_group" "cluster" {
  name        = "${var.cluster_name}-cluster"
  description = "KTHW server and worker nodes"
  vpc_id      = aws_vpc.this.id
}

resource "aws_vpc_security_group_egress_rule" "eice_to_jumpbox" {
  security_group_id            = aws_security_group.eice.id
  description                  = "SSH tunnels to the jumpbox"
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = aws_security_group.jumpbox.id
}

resource "aws_vpc_security_group_ingress_rule" "jumpbox_from_eice" {
  security_group_id            = aws_security_group.jumpbox.id
  description                  = "SSH from the EC2 Instance Connect Endpoint"
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = aws_security_group.eice.id
}

locals {
  # Ports the jumpbox uses on cluster members: SSH (labs 3-11), the API
  # server (lab 10), NodePorts (lab 12 smoke test).
  jumpbox_to_cluster = {
    ssh       = { from = 22, to = 22 }
    apiserver = { from = 6443, to = 6443 }
    nodeports = { from = 30000, to = 32767 }
  }
  # Package mirrors, release downloads and container registries, via NAT.
  internet_egress = {
    http  = 80
    https = 443
  }
  pod_cidr = "10.200.0.0/16"
}

resource "aws_vpc_security_group_egress_rule" "jumpbox_to_cluster" {
  for_each = local.jumpbox_to_cluster

  security_group_id            = aws_security_group.jumpbox.id
  description                  = "To cluster: ${each.key}"
  ip_protocol                  = "tcp"
  from_port                    = each.value.from
  to_port                      = each.value.to
  referenced_security_group_id = aws_security_group.cluster.id
}

resource "aws_vpc_security_group_ingress_rule" "cluster_from_jumpbox" {
  for_each = local.jumpbox_to_cluster

  security_group_id            = aws_security_group.cluster.id
  description                  = "From jumpbox: ${each.key}"
  ip_protocol                  = "tcp"
  from_port                    = each.value.from
  to_port                      = each.value.to
  referenced_security_group_id = aws_security_group.jumpbox.id
}

resource "aws_vpc_security_group_egress_rule" "jumpbox_internet" {
  for_each = local.internet_egress

  security_group_id = aws_security_group.jumpbox.id
  description       = "Internet ${each.key} via NAT"
  ip_protocol       = "tcp"
  from_port         = each.value
  to_port           = each.value
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "cluster_internet" {
  for_each = local.internet_egress

  security_group_id = aws_security_group.cluster.id
  description       = "Internet ${each.key} via NAT"
  ip_protocol       = "tcp"
  from_port         = each.value
  to_port           = each.value
  cidr_ipv4         = "0.0.0.0/0"
}

# Control plane <-> kubelets, and node-to-node pod traffic over lab 11's routes.
resource "aws_vpc_security_group_ingress_rule" "cluster_self" {
  security_group_id            = aws_security_group.cluster.id
  description                  = "Cluster members to each other"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.cluster.id
}

resource "aws_vpc_security_group_egress_rule" "cluster_self" {
  security_group_id            = aws_security_group.cluster.id
  description                  = "Cluster members to each other"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.cluster.id
}

# Pod source addresses are not ENI addresses, so the self rule doesn't match them.
resource "aws_vpc_security_group_ingress_rule" "cluster_pods" {
  security_group_id = aws_security_group.cluster.id
  description       = "Pod network (KTHW lab 11 routes)"
  ip_protocol       = "-1"
  cidr_ipv4         = local.pod_cidr
}

resource "aws_vpc_security_group_egress_rule" "cluster_pods" {
  security_group_id = aws_security_group.cluster.id
  description       = "Pod network (KTHW lab 11 routes)"
  ip_protocol       = "-1"
  cidr_ipv4         = local.pod_cidr
}
