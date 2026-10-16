# One role per machine, each limited to the SSM parameters that machine owns
# or must read (AC-6). Public keys only: no private key ever leaves the
# machine that generated it, and none is in Terraform state.
locals {
  param_arn_prefix = "arn:${local.partition}:ssm:${var.region}:${local.account_id}:parameter${local.ssm_prefix}"
  jumpbox_key_arn  = "${local.param_arn_prefix}/jumpbox/root-ssh-public-key"
}

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "machine" {
  for_each = local.machines

  name               = "${var.cluster_name}-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

data "aws_iam_policy_document" "machine" {
  for_each = local.machines

  # Publish this machine's own key: the jumpbox's root key, or a member's host key.
  statement {
    sid     = "PublishOwnKey"
    actions = ["ssm:PutParameter"]
    resources = [each.key == "jumpbox"
      ? local.jumpbox_key_arn
      : "${local.param_arn_prefix}/hosts/${each.key}/ssh-host-ed25519-key"
    ]
  }

  # The jumpbox reads members' host keys (known_hosts); members read the jumpbox key.
  statement {
    sid     = "ReadPeerKeys"
    actions = ["ssm:GetParameter"]
    resources = each.key == "jumpbox" ? [
      for m in keys(local.cluster_members) : "${local.param_arn_prefix}/hosts/${m}/ssh-host-ed25519-key"
    ] : [local.jumpbox_key_arn]
  }
}

resource "aws_iam_role_policy" "machine" {
  for_each = local.machines

  name   = "ssh-key-exchange"
  role   = aws_iam_role.machine[each.key].id
  policy = data.aws_iam_policy_document.machine[each.key].json
}

resource "aws_iam_instance_profile" "machine" {
  for_each = local.machines

  name = "${var.cluster_name}-${each.key}"
  role = aws_iam_role.machine[each.key].name
}
