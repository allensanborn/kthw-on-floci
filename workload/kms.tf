# One customer-managed key for this cluster's data at rest: EBS volumes, the
# flow-log group and the SSH key parameters (SC-12, SC-13, SC-28).
data "aws_iam_policy_document" "kms" {
  #checkov:skip=CKV_AWS_109:A key policy's "*" resource is the key itself; access is scoped by principal and condition
  #checkov:skip=CKV_AWS_111:Same: key policy, not an identity policy
  #checkov:skip=CKV_AWS_356:Same: key policy, not an identity policy
  statement {
    sid       = "AccountAdministration"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
  }

  statement {
    sid = "CloudWatchLogsFlowLogGroup"
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*",
    ]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["logs.${var.region}.amazonaws.com"]
    }
    condition {
      test     = "ArnEquals"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:${local.partition}:logs:${var.region}:${local.account_id}:log-group:/${var.cluster_name}/vpc-flow-logs"]
    }
  }
}

resource "aws_kms_key" "this" {
  description             = "${var.cluster_name}: EBS volumes, VPC flow logs, SSH key parameters"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.kms.json
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.cluster_name}"
  target_key_id = aws_kms_key.this.key_id
}
