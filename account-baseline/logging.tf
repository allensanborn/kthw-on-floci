# Audit logging (AU-2, AU-3, AU-6, AU-9, AU-11, AU-12): a multi-region CloudTrail with
# log file validation, encrypted with a customer-managed key, delivered to S3 (with
# access logging) and to CloudWatch Logs for alerting.

locals {
  trail_name = "${var.name_prefix}-account"
  trail_arn  = "arn:${local.partition}:cloudtrail:${var.region}:${local.account_id}:trail/${local.trail_name}"
  log_group  = "/${var.name_prefix}/cloudtrail"
  # The cloudposse buckets' names are "<name_prefix>-<key>".
  audit_buckets = toset(["cloudtrail", "config"])
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
    sid       = "EventBridgePublishesFindingsToTheEncryptedTopic"
    actions   = ["kms:GenerateDataKey*", "kms:Decrypt"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }

  # Not what this account's Config uses: it delivers through its IAM role, which has its
  # own grant (detection.tf). This covers Config's service principal, which delivers when
  # Config runs with its service-linked role instead.
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

# The modules grant CloudTrail and Config write access to both audit buckets, to any key and
# with no source condition, so another account's trail could deliver into them (confused
# deputy, AU-9). These denies override that: each bucket takes only its own service, only
# on this account's behalf, and only under that service's AWSLogs/<account>/ prefix (the
# path scoping Gruntwork uses, as a second layer). Both services send the condition keys
# used: AWS's own bucket policies for them require aws:SourceArn (CloudTrail) and
# aws:SourceAccount (Config). Config delivers through its IAM role, not this principal,
# so these never block this account's Config.
locals {
  audit_delivery = {
    cloudtrail = {
      service = "cloudtrail.amazonaws.com"
      other   = "config.amazonaws.com"
      prefix  = "AWSLogs/${local.account_id}/*"
      source  = { variable = "aws:SourceArn", value = local.trail_arn }
    }
    config = {
      service = "config.amazonaws.com"
      other   = "cloudtrail.amazonaws.com"
      prefix  = "AWSLogs/${local.account_id}/Config/*"
      source  = { variable = "aws:SourceAccount", value = local.account_id }
    }
  }
}

data "aws_iam_policy_document" "audit_bucket_source" {
  for_each = local.audit_buckets

  statement {
    sid     = "DenyTheOtherLogService"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      "arn:${local.partition}:s3:::${var.name_prefix}-${each.key}",
      "arn:${local.partition}:s3:::${var.name_prefix}-${each.key}/*",
    ]
    principals {
      type        = "Service"
      identifiers = [local.audit_delivery[each.key].other]
    }
  }

  statement {
    sid     = "DenyDeliveriesForOtherSources"
    effect  = "Deny"
    actions = ["s3:PutObject", "s3:GetBucketAcl", "s3:ListBucket"]
    resources = [
      "arn:${local.partition}:s3:::${var.name_prefix}-${each.key}",
      "arn:${local.partition}:s3:::${var.name_prefix}-${each.key}/*",
    ]
    principals {
      type        = "Service"
      identifiers = [local.audit_delivery[each.key].service]
    }
    condition {
      test     = "StringNotEquals"
      variable = local.audit_delivery[each.key].source.variable
      values   = [local.audit_delivery[each.key].source.value]
    }
  }

  statement {
    sid           = "DenyDeliveriesOutsideTheAccountPrefix"
    effect        = "Deny"
    actions       = ["s3:PutObject"]
    not_resources = ["arn:${local.partition}:s3:::${var.name_prefix}-${each.key}/${local.audit_delivery[each.key].prefix}"]
    principals {
      type        = "Service"
      identifiers = [local.audit_delivery[each.key].service]
    }
  }
}

module "trail_bucket" {
  # v0.33.0, pinned by commit: a registry version is a movable git tag.
  source = "git::https://github.com/cloudposse/terraform-aws-cloudtrail-s3-bucket.git?ref=57d406179c9adfcaeca5c3d91d8f71200353b5d4"

  namespace = var.name_prefix
  name      = "cloudtrail"

  # Overrides where the module's defaults fall short of the bar:
  sse_algorithm          = "aws:kms" # default AES256; SC-28 with a customer-managed key
  kms_master_key_arn     = aws_kms_key.audit.arn
  versioning_enabled     = true                                           # default false; AU-9 protection of audit information
  access_log_bucket_name = aws_s3_bucket.access_logs["cloudtrail"].bucket # AU-2: access to the logs is itself logged
  expiration_days        = var.log_retention_days
  # M-21-31's 12 active months, then cold storage (default: no Glacier transition).
  enable_glacier_transition = true
  glacier_transition_days   = 365
  force_destroy             = false # kept explicit: audit logs are never deleted with the stack
  policy                    = data.aws_iam_policy_document.audit_bucket_source["cloudtrail"].json
}

# --- S3 server access logs for the two audit buckets (AU-2) -------------------
# Not the modules' own access-log buckets: those inherit the audit bucket's SSE-KMS, and
# server access logging cannot deliver to an SSE-KMS bucket. SSE-S3, as in bootstrap/.

resource "aws_s3_bucket" "access_logs" {
  #checkov:skip=CKV_AWS_144:Exception E-5 (docs/exceptions.md): single-region learning environment; production replicates logs to a second region
  #checkov:skip=CKV_AWS_145:S3 server access logging cannot deliver to an SSE-KMS bucket; SSE-S3 is the only option
  #checkov:skip=CKV_AWS_18:Exception E-14 (docs/exceptions.md): a log bucket logging into itself recurses
  for_each = local.audit_buckets

  bucket = "${var.name_prefix}-${each.key}-s3-access-logs"
}

resource "aws_s3_bucket_public_access_block" "access_logs" {
  for_each = local.audit_buckets

  bucket                  = aws_s3_bucket.access_logs[each.key].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "access_logs" {
  for_each = local.audit_buckets

  bucket = aws_s3_bucket.access_logs[each.key].id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "access_logs" {
  for_each = local.audit_buckets

  bucket = aws_s3_bucket.access_logs[each.key].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  for_each = local.audit_buckets

  bucket = aws_s3_bucket.access_logs[each.key].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "access_logs" {
  for_each = local.audit_buckets

  bucket = aws_s3_bucket.access_logs[each.key].id
  rule {
    id     = "expire"
    status = "Enabled"
    filter {}
    expiration {
      days = var.log_retention_days
    }
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_notification" "access_logs" {
  for_each = local.audit_buckets

  bucket      = aws_s3_bucket.access_logs[each.key].id
  eventbridge = true
}

data "aws_iam_policy_document" "access_logs" {
  for_each = local.audit_buckets

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.access_logs[each.key].arn, "${aws_s3_bucket.access_logs[each.key].arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid       = "S3ServerAccessLogs"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.access_logs[each.key].arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${local.partition}:s3:::${var.name_prefix}-${each.key}"]
    }
  }
}

resource "aws_s3_bucket_policy" "access_logs" {
  for_each = local.audit_buckets

  bucket     = aws_s3_bucket.access_logs[each.key].id
  policy     = data.aws_iam_policy_document.access_logs[each.key].json
  depends_on = [aws_s3_bucket_public_access_block.access_logs]
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

  # The trail delivers to CloudWatch Logs through this role from its first event. The
  # provider retries CreateTrail while IAM propagates, but only once the policy exists.
  depends_on = [aws_iam_role_policy.trail_to_logs]
}
