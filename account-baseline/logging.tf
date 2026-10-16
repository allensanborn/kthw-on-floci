# Audit logging (AU-2, AU-3, AU-6, AU-9, AU-11, AU-12): a multi-region CloudTrail with
# log file validation, encrypted with a customer-managed key, delivered to S3 (with
# access logging) and to CloudWatch Logs for alerting.

locals {
  trail_name = "${var.name_prefix}-account"
  trail_arn  = "arn:${local.partition}:cloudtrail:${var.region}:${local.account_id}:trail/${local.trail_name}"
  log_group  = "/${var.name_prefix}/cloudtrail"
}

data "aws_iam_policy_document" "audit_key" {
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
    sid       = "CloudTrailEncryptsThisAccountsTrail"
    actions   = ["kms:GenerateDataKey*"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:aws:cloudtrail:arn"
      values   = ["arn:${local.partition}:cloudtrail:*:${local.account_id}:trail/*"]
    }
  }

  statement {
    sid       = "CloudTrailDescribesTheKey"
    actions   = ["kms:DescribeKey"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }

  statement {
    sid       = "CloudWatchLogsEncryptsTheTrailLogGroup"
    actions   = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["logs.${var.region}.amazonaws.com"]
    }
    condition {
      test     = "ArnEquals"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:${local.partition}:logs:${var.region}:${local.account_id}:log-group:${local.log_group}"]
    }
  }

  statement {
    sid       = "CloudWatchAlarmsPublishToTheEncryptedTopic"
    actions   = ["kms:GenerateDataKey*", "kms:Decrypt"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }

  statement {
    sid       = "ConfigDeliversEncrypted"
    actions   = ["kms:GenerateDataKey*", "kms:Decrypt"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_kms_key" "audit" {
  description             = "${var.name_prefix}: CloudTrail, its log group, and AWS Config"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.audit_key.json
}

resource "aws_kms_alias" "audit" {
  name          = "alias/${var.name_prefix}-audit"
  target_key_id = aws_kms_key.audit.key_id
}

module "trail_bucket" {
  # v0.33.0, pinned by commit: a registry version is a movable git tag.
  source = "git::https://github.com/cloudposse/terraform-aws-cloudtrail-s3-bucket.git?ref=57d406179c9adfcaeca5c3d91d8f71200353b5d4"

  namespace = var.name_prefix
  name      = "cloudtrail"

  # Overrides where the module's defaults fall short of the bar:
  sse_algorithm            = "aws:kms" # default AES256; SC-28 with a customer-managed key
  kms_master_key_arn       = aws_kms_key.audit.arn
  versioning_enabled       = true # default false; AU-9 protection of audit information
  create_access_log_bucket = true # default false; AU-2 access to the logs is itself logged
  expiration_days          = var.log_retention_days
  force_destroy            = false # kept explicit: audit logs are never deleted with the stack
}

resource "aws_cloudwatch_log_group" "trail" {
  name              = local.log_group
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.audit.arn
}

data "aws_iam_policy_document" "trail_to_logs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }
}

resource "aws_iam_role" "trail_to_logs" {
  name               = "${var.name_prefix}-cloudtrail-to-logs"
  assume_role_policy = data.aws_iam_policy_document.trail_to_logs_assume.json
}

data "aws_iam_policy_document" "trail_to_logs" {
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.trail.arn}:log-stream:*"]
  }
}

resource "aws_iam_role_policy" "trail_to_logs" {
  name   = "deliver"
  role   = aws_iam_role.trail_to_logs.id
  policy = data.aws_iam_policy_document.trail_to_logs.json
}

module "cloudtrail" {
  # 0.24.0, pinned by commit: a registry version is a movable git tag.
  source = "git::https://github.com/cloudposse/terraform-aws-cloudtrail.git?ref=7610c670673c06835accf54d665e5f710dac4b2f"

  namespace = var.name_prefix
  name      = "account"

  s3_bucket_name                = module.trail_bucket.bucket_id
  kms_key_arn                   = aws_kms_key.audit.arn
  enable_log_file_validation    = true # AU-9(3); module default, kept explicit
  is_multi_region_trail         = true
  include_global_service_events = true # default false; IAM and STS events are global
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.trail.arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.trail_to_logs.arn

  # Management events, and S3 object-level reads and writes (AU-2, AU-12; CIS 3.x
  # CloudTrail.7 / S3.22-23), except CloudTrail's own deliveries to its bucket.
  advanced_event_selector = [
    {
      name           = "Management events"
      field_selector = [{ field = "eventCategory", equals = ["Management"] }]
    },
    {
      name = "S3 object-level events"
      field_selector = [
        { field = "eventCategory", equals = ["Data"] },
        { field = "resources.type", equals = ["AWS::S3::Object"] },
        { field = "resources.ARN", not_starts_with = ["${module.trail_bucket.bucket_arn}/"] },
      ]
    },
  ]
}
