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
