# Configuration monitoring and threat detection (CM-2, CM-8, SI-4, RA-5, CA-7).

module "config_bucket" {
  # v0.33.0, pinned by commit: a registry version is a movable git tag.
  source = "git::https://github.com/cloudposse/terraform-aws-cloudtrail-s3-bucket.git?ref=57d406179c9adfcaeca5c3d91d8f71200353b5d4"

  namespace = var.name_prefix
  name      = "config"

  sse_algorithm          = "aws:kms"
  kms_master_key_arn     = aws_kms_key.audit.arn
  versioning_enabled     = true
  access_log_bucket_name = aws_s3_bucket.access_logs["config"].bucket
  expiration_days        = var.log_retention_days
  force_destroy          = false
  policy                 = data.aws_iam_policy_document.audit_bucket_source["config"].json
}

locals {
  # AWS managed rules for the controls this repo's workload claims, so AWS Config reports
  # drift from them continuously (CA-7).
  config_rules = {
    "ec2-imdsv2-check"                      = "EC2_IMDSV2_CHECK"
    "encrypted-volumes"                     = "ENCRYPTED_VOLUMES"
    "ec2-ebs-encryption-by-default"         = "EC2_EBS_ENCRYPTION_BY_DEFAULT"
    "vpc-flow-logs-enabled"                 = "VPC_FLOW_LOGS_ENABLED"
    "vpc-default-security-group-closed"     = "VPC_DEFAULT_SECURITY_GROUP_CLOSED"
    "restricted-ssh"                        = "INCOMING_SSH_DISABLED"
    "ec2-instance-no-public-ip"             = "EC2_INSTANCE_NO_PUBLIC_IP"
    "cloudtrail-enabled"                    = "CLOUD_TRAIL_ENABLED"
    "cloud-trail-encryption-enabled"        = "CLOUD_TRAIL_ENCRYPTION_ENABLED"
    "cloud-trail-log-file-validation"       = "CLOUD_TRAIL_LOG_FILE_VALIDATION_ENABLED"
    "s3-bucket-ssl-requests-only"           = "S3_BUCKET_SSL_REQUESTS_ONLY"
    "s3-account-level-public-access-blocks" = "S3_ACCOUNT_LEVEL_PUBLIC_ACCESS_BLOCKS_PERIODIC"
    "iam-password-policy"                   = "IAM_PASSWORD_POLICY"
    "cmk-backing-key-rotation-enabled"      = "CMK_BACKING_KEY_ROTATION_ENABLED"
    "cloudwatch-log-group-encrypted"        = "CLOUDWATCH_LOG_GROUP_ENCRYPTED"
  }
}

module "config" {
  # v2.0.0, pinned by commit: a registry version is a movable git tag.
  source = "git::https://github.com/cloudposse/terraform-aws-config.git?ref=340908e44d96d32c6436430299e09bd1ac107300"

  namespace = var.name_prefix
  name      = "config"

  s3_bucket_id                     = module.config_bucket.bucket_id
  s3_bucket_arn                    = module.config_bucket.bucket_arn
  s3_kms_key_arn                   = aws_kms_key.audit.arn
  create_iam_role                  = true # default false
  global_resource_collector_region = var.region
  managed_rules = { for name, identifier in local.config_rules : name => {
    description      = "AWS managed rule ${identifier}"
    identifier       = identifier
    input_parameters = {}
    enabled          = true
    tags             = {}
  } }
}

# Config delivers through the module's IAM role, not its service principal, so the key
# policy's ConfigDeliversEncrypted grant does not cover delivery: the role needs the key.
# The key policy delegates to IAM, so this role policy is enough.
data "aws_iam_policy_document" "config_audit_key" {
  statement {
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = [aws_kms_key.audit.arn]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${var.region}.${data.aws_partition.current.dns_suffix}"]
    }
  }
}

resource "aws_iam_role_policy" "config_audit_key" {
  name   = "audit-key"
  role   = reverse(split("/", module.config.iam_role))[0]
  policy = data.aws_iam_policy_document.config_audit_key.json
}

module "guardduty" {
  # v1.0.0, pinned by commit: a registry version is a movable git tag.
  source = "git::https://github.com/cloudposse/terraform-aws-guardduty.git?ref=2502c87d542fc3639b372ef87e3445da75df18d9"

  namespace = var.name_prefix
  name      = "guardduty"

  finding_publishing_frequency                    = "FIFTEEN_MINUTES" # default (null) is six hours
  s3_protection_enabled                           = true
  malware_protection_scan_ec2_ebs_volumes_enabled = true
  # Runtime monitoring installs an agent on the instances and is billed per vCPU; off, documented.
  runtime_monitoring_enabled = false
}

module "security_hub" {
  # v0.13.0, pinned by commit: a registry version is a movable git tag.
  source = "git::https://github.com/cloudposse/terraform-aws-security-hub.git?ref=d5642ecdda292c14289fe750854ce50c6ea530d8"

  namespace = var.name_prefix
  name      = "securityhub"

  enable_default_standards = false # explicit list instead
  enabled_standards = [
    "standards/aws-foundational-security-best-practices/v/1.0.0",
    "standards/cis-aws-foundations-benchmark/v/3.0.0",
    "standards/nist-800-53/v/5.0.0",
  ]
}
