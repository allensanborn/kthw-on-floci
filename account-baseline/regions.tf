# The regional detectors in every other enabled region (SI-4, CM-8, SC-28, CA-7): a key
# used in a region nobody watches would go unseen. Same settings as the home region,
# through the provider's per-resource `region` argument, so no provider per region.
# Security Hub stays in the home region (E-19).

data "aws_regions" "enabled" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required", "opted-in"]
  }
}

locals {
  other_regions = setsubtract(data.aws_regions.enabled.names, [var.region])
}

resource "aws_guardduty_detector" "other" {
  for_each = local.other_regions

  region                       = each.key
  enable                       = true
  finding_publishing_frequency = "FIFTEEN_MINUTES"
}

resource "aws_guardduty_detector_feature" "other" {
  for_each = { for p in setproduct(local.other_regions, ["S3_DATA_EVENTS", "EBS_MALWARE_PROTECTION"]) : "${p[0]}/${p[1]}" => p }

  region      = each.value[0]
  detector_id = aws_guardduty_detector.other[each.value[0]].id
  name        = each.value[1]
  status      = "ENABLED"
}

resource "aws_ebs_encryption_by_default" "other" {
  for_each = local.other_regions

  region  = each.key
  enabled = true
}

resource "aws_accessanalyzer_analyzer" "other" {
  for_each = local.other_regions

  region        = each.key
  analyzer_name = "${var.name_prefix}-account"
  type          = "ACCOUNT"
}

# Config records each region's resources (global ones only in the home region, as there)
# and delivers to the home region's bucket, through the same role and key.
resource "aws_config_configuration_recorder" "other" {
  for_each = local.other_regions

  region   = each.key
  name     = "${var.name_prefix}-config"
  role_arn = module.config.iam_role
  recording_group {
    all_supported                 = true
    include_global_resource_types = false
  }
}

resource "aws_config_delivery_channel" "other" {
  for_each = local.other_regions

  region         = each.key
  name           = "${var.name_prefix}-config"
  s3_bucket_name = module.config_bucket.bucket_id
  s3_kms_key_arn = aws_kms_key.audit.arn
  depends_on     = [aws_config_configuration_recorder.other, aws_iam_role_policy.config_audit_key]
}

resource "aws_config_configuration_recorder_status" "other" {
  for_each = local.other_regions

  region     = each.key
  name       = aws_config_configuration_recorder.other[each.key].name
  is_enabled = true
  depends_on = [aws_config_delivery_channel.other]
}
