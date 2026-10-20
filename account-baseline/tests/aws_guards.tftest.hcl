# Offline guards for fixes floci cannot test (it does not deliver logs or evaluate KMS
# and bucket policies). A mocked provider: no credentials, no emulator. Each run names
# the fix it keeps in place (5885815).

# Where a failing assertion over a whole for_each collection made Terraform 1.15.8 panic
# while printing it ("value has marks, so it cannot be serialized as JSON") instead of
# reporting the failure, the assertion names each instance by a literal key.

mock_provider "aws" {
  # Policy documents are asserted on their arguments, so any valid JSON will do here.
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  # The cloudposse modules look these up too, and validate what they build from them.
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111122223333" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com" }
  }
  mock_data "aws_region" {
    defaults = { name = "us-east-1", region = "us-east-1" }
  }
  mock_data "aws_regions" {
    defaults = { names = ["us-east-1", "us-west-2", "eu-north-1"] }
  }
  mock_data "aws_iam_policy" {
    defaults = { arn = "arn:aws:iam::aws:policy/mock" }
  }
}

run "access_log_buckets_use_sse_s3" {
  command = plan

  # S3 server access logging cannot deliver to an SSE-KMS bucket; the modules' own
  # access-log buckets inherited SSE-KMS, so these replace them.
  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.access_logs["cloudtrail"].rule).apply_server_side_encryption_by_default).sse_algorithm == "AES256"
    error_message = "The cloudtrail access-log bucket must use SSE-S3 (AES256)."
  }
  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.access_logs["config"].rule).apply_server_side_encryption_by_default).sse_algorithm == "AES256"
    error_message = "The config access-log bucket must use SSE-S3 (AES256)."
  }
}

run "config_role_may_use_the_audit_key" {
  command = plan

  # Config delivers through the module's role, which the key policy's service grant
  # does not cover: without this, every snapshot fails with AccessDenied.
  assert {
    condition = anytrue([for s in data.aws_iam_policy_document.config_audit_key.statement :
    contains(s.actions, "kms:GenerateDataKey") && contains(s.actions, "kms:Decrypt")])
    error_message = "The Config role needs kms:GenerateDataKey and kms:Decrypt on the audit key."
  }
}

run "audit_buckets_take_only_their_own_service_and_account" {
  command = plan

  # Without source conditions, another account's trail or Config can deliver here; without
  # path scoping, anything under the bucket. CloudTrail is pinned to this account's trail.
  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.audit_bucket_source["cloudtrail"].statement : s.effect == "Deny" && anytrue([
        for c in s.condition : c.variable == "aws:SourceArn" && c.test == "StringNotEquals" && contains(c.values, "arn:aws:cloudtrail:us-east-1:111122223333:trail/kthw-account")
      ])
    ])
    error_message = "The cloudtrail bucket must deny deliveries whose aws:SourceArn is not this account's trail."
  }
  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.audit_bucket_source["config"].statement : s.effect == "Deny" && anytrue([
        for c in s.condition : c.variable == "aws:SourceAccount" && c.test == "StringNotEquals" && contains(c.values, "111122223333")
      ])
    ])
    error_message = "The config bucket must deny deliveries whose aws:SourceAccount is not this account."
  }
  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.audit_bucket_source["cloudtrail"].statement :
      s.effect == "Deny" && contains(coalesce(s.not_resources, []), "arn:aws:s3:::kthw-cloudtrail/AWSLogs/111122223333/*")
    ])
    error_message = "The cloudtrail bucket must deny writes outside AWSLogs/<account>/."
  }
  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.audit_bucket_source["config"].statement :
      s.effect == "Deny" && contains(coalesce(s.not_resources, []), "arn:aws:s3:::kthw-config/AWSLogs/111122223333/Config/*")
    ])
    error_message = "The config bucket must deny writes outside AWSLogs/<account>/Config/."
  }
}

run "findings_reach_the_alarm_topic" {
  command = plan

  # GuardDuty and Security Hub findings were neither exported nor alerted (kthw-q85.27).
  assert {
    condition     = jsondecode(aws_cloudwatch_event_rule.findings["guardduty"].event_pattern).source == ["aws.guardduty"]
    error_message = "A rule must match GuardDuty findings."
  }
  assert {
    condition     = jsondecode(aws_cloudwatch_event_rule.findings["securityhub"].event_pattern).source == ["aws.securityhub"]
    error_message = "A rule must match Security Hub findings."
  }
  assert {
    condition     = aws_cloudwatch_event_target.findings["guardduty"].rule == "kthw-guardduty-findings" && aws_cloudwatch_event_target.findings["securityhub"].rule == "kthw-securityhub-findings"
    error_message = "Each finding rule needs a target."
  }
  # The topic is encrypted with the audit key: EventBridge must be able to use it.
  assert {
    condition = anytrue([for s in data.aws_iam_policy_document.audit_key.statement :
      anytrue([for p in s.principals : contains(p.identifiers, "events.amazonaws.com")])
    && contains(s.actions, "kms:GenerateDataKey*")])
    error_message = "The audit key must let EventBridge publish to the encrypted topic."
  }
  assert {
    condition = anytrue([for s in data.aws_iam_policy_document.security_alarms.statement :
    contains(s.actions, "sns:Publish") && anytrue([for p in s.principals : contains(p.identifiers, "events.amazonaws.com") && contains(p.identifiers, "cloudwatch.amazonaws.com")])])
    error_message = "The topic policy must let EventBridge and CloudWatch publish."
  }
}

run "audit_logs_kept_30_months" {
  command = plan

  # OMB M-21-31 (FedRAMP AU-11): 12 months active and 18 cold (kthw-q85.28).
  assert {
    condition     = aws_cloudwatch_log_group.trail.retention_in_days >= 913
    error_message = "The trail's log group must keep at least 30 months."
  }
  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.access_logs["cloudtrail"].rule[0].expiration).days >= 913 && one(aws_s3_bucket_lifecycle_configuration.access_logs["config"].rule[0].expiration).days >= 913
    error_message = "The access-log buckets must keep at least 30 months."
  }
  assert {
    condition     = var.log_retention_days >= 913
    error_message = "log_retention_days (the trail and Config buckets' expiry) must be at least 30 months."
  }
}

run "detectors_run_in_every_enabled_region" {
  command = plan

  # A region nobody watches hides whatever runs there (kthw-q85.26). The home region is
  # the modules'; every other enabled region gets the same detectors here.
  assert {
    condition     = aws_guardduty_detector.other["us-west-2"].enable && aws_ebs_encryption_by_default.other["us-west-2"].enabled && aws_accessanalyzer_analyzer.other["us-west-2"].region == "us-west-2" && aws_config_configuration_recorder_status.other["us-west-2"].is_enabled
    error_message = "GuardDuty, EBS default encryption, Access Analyzer and Config must run in us-west-2."
  }
  assert {
    condition     = aws_guardduty_detector.other["eu-north-1"].enable && aws_ebs_encryption_by_default.other["eu-north-1"].enabled && aws_accessanalyzer_analyzer.other["eu-north-1"].region == "eu-north-1" && aws_config_configuration_recorder_status.other["eu-north-1"].is_enabled
    error_message = "GuardDuty, EBS default encryption, Access Analyzer and Config must run in eu-north-1."
  }
  assert {
    condition     = !can(aws_guardduty_detector.other["us-east-1"])
    error_message = "The home region's detectors come from the modules, not the per-region set."
  }
}
