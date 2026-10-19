# One role per machine, each limited to the SSM parameters that machine owns
# or must read (AC-6). Public keys only: no private key ever leaves the
# machine that generated it, and none is in Terraform state.

# Terraform owns each key parameter's lifecycle: created "pending" before any machine boots,
# deleted on destroy, so a rebuilt cluster can never read the previous cluster's keys. The
# machines write the values (ignore_changes), as SecureString under the cluster key: a value
# the nodes trust can only be written by a principal that may also use that key (E-16).
resource "aws_ssm_parameter" "ssh_key" {
  for_each = local.machines

  name   = each.key == "jumpbox" ? "${local.ssm_prefix}/jumpbox/root-ssh-public-key" : "${local.ssm_prefix}/hosts/${each.key}/ssh-host-ed25519-key"
  type   = "SecureString"
  key_id = aws_kms_alias.this.name
  value  = "pending"

  lifecycle {
    ignore_changes = [value]
  }
}

locals {
  # The jumpbox reads members' host keys (known_hosts); members read the jumpbox key.
  peer_key_arns = { for k in keys(local.machines) : k => k == "jumpbox"
    ? [for m in keys(local.cluster_members) : aws_ssm_parameter.ssh_key[m].arn]
    : [aws_ssm_parameter.ssh_key["jumpbox"].arn]
  }
  ssm_via = "ssm.${var.region}.${data.aws_partition.current.dns_suffix}"
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

  # Publish this machine's own key (the jumpbox's root key, or a member's host key), and
  # read it back, so a value is written only when it changed.
  statement {
    sid       = "PublishOwnKey"
    actions   = ["ssm:PutParameter", "ssm:GetParameter"]
    resources = [aws_ssm_parameter.ssh_key[each.key].arn]
  }

  statement {
    sid       = "ReadPeerKeys"
    actions   = ["ssm:GetParameter"]
    resources = local.peer_key_arns[each.key]
  }

  # SecureString: SSM encrypts and decrypts with the cluster key on the machine's behalf,
  # with the parameter's ARN as encryption context, so each grant covers named parameters only.
  statement {
    sid       = "EncryptOwnKey"
    actions   = ["kms:Encrypt"]
    resources = [aws_kms_key.this.arn]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = [local.ssm_via]
    }
    condition {
      test     = "StringEquals"
      variable = "kms:EncryptionContext:PARAMETER_ARN"
      values   = [aws_ssm_parameter.ssh_key[each.key].arn]
    }
  }

  statement {
    sid       = "DecryptKeys"
    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.this.arn]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = [local.ssm_via]
    }
    condition {
      test     = "StringEquals"
      variable = "kms:EncryptionContext:PARAMETER_ARN"
      values   = concat([aws_ssm_parameter.ssh_key[each.key].arn], local.peer_key_arns[each.key])
    }
  }

  # A value encrypted with any other key (aws/ssm needs no IAM grant) is never accepted.
  statement {
    sid           = "DecryptOnlyWithTheClusterKey"
    effect        = "Deny"
    actions       = ["kms:Decrypt"]
    not_resources = [aws_kms_key.this.arn]
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
