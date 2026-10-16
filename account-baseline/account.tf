# Account-wide settings that need no module (CIS AWS Foundations 3.0 section 1 and 2).

resource "aws_iam_account_password_policy" "this" {
  minimum_password_length        = 14 # CIS 1.8
  require_lowercase_characters   = true
  require_uppercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  allow_users_to_change_password = true
  password_reuse_prevention      = 24 # CIS 1.9
  max_password_age               = 90
}

resource "aws_ebs_encryption_by_default" "this" {
  enabled = true # CIS 2.2.1, SC-28
}

resource "aws_s3_account_public_access_block" "this" {
  block_public_acls       = true # CIS 2.1.4
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_accessanalyzer_analyzer" "this" {
  analyzer_name = "${var.name_prefix}-account" # CIS 1.20
  type          = "ACCOUNT"
}
