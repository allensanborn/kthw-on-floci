# The account's default VPC, where one exists (every new AWS account has one; floci always
# does): nothing runs there, so its default security group and network ACL deny all
# (CIS 5.4; Security Hub EC2.2, EC2.21).
data "aws_vpcs" "default" {
  filter {
    name   = "is-default"
    values = ["true"]
  }
}

data "aws_vpc" "default" {
  for_each = toset(data.aws_vpcs.default.ids)
  id       = each.value
}

resource "aws_default_security_group" "default_vpc" {
  for_each = data.aws_vpc.default
  vpc_id   = each.value.id
}

data "aws_network_acls" "default_vpc" {
  for_each = data.aws_vpc.default
  vpc_id   = each.value.id

  filter {
    name   = "default"
    values = ["true"]
  }
}

resource "aws_default_network_acl" "default_vpc" {
  for_each               = data.aws_vpc.default
  default_network_acl_id = one(data.aws_network_acls.default_vpc[each.key].ids) # no rules: deny all

  lifecycle {
    ignore_changes = [subnet_ids]
  }
}
