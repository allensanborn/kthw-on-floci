# Offline guards for fixes floci cannot test (it does not route, enforce KMS or hang on
# detach). A mocked provider: no credentials, no emulator. Each run names the review
# finding it keeps fixed; .scratch/review is local, the commits say the same.

# Where a failing assertion over a whole for_each collection made Terraform 1.15.8 panic
# while printing it ("value has marks, so it cannot be serialized as JSON") instead of
# reporting the failure, the assertion names each instance by a literal key.

mock_provider "aws" {
  # Policy documents are asserted on their arguments, so any valid JSON will do here.
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  # The provider validates ARNs it is handed, so these need ARN-shaped values.
  mock_resource "aws_kms_key" {
    defaults = { arn = "arn:aws-cn:kms:cn-north-1:111122223333:key/mock" }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = { arn = "arn:aws-cn:logs:cn-north-1:111122223333:log-group:mock" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws-cn:iam::111122223333:role/mock" }
  }
  override_data {
    target = data.aws_partition.current
    values = { partition = "aws-cn", dns_suffix = "amazonaws.com.cn" }
  }
  override_data {
    target = data.aws_caller_identity.current
    values = { account_id = "111122223333" }
  }
  override_data {
    target = data.aws_availability_zones.available
    values = { names = ["cn-north-1a"] }
  }
  override_data {
    target = data.aws_ami.debian
    values = { id = "ami-12345678" }
  }
}

variables {
  region = "cn-north-1"
}

run "ssh_key_parameters_are_terraform_owned_secure_strings" {
  command = apply

  # Stale keys after destroy/apply (4abee99): Terraform creates every parameter as
  # "pending" under the cluster key, and only the machines write the real value.
  assert {
    condition = alltrue([for k in ["jumpbox", "server", "node-0", "node-1"] :
      aws_ssm_parameter.ssh_key[k].type == "SecureString" && aws_ssm_parameter.ssh_key[k].value == "pending"
    && aws_ssm_parameter.ssh_key[k].key_id == aws_kms_alias.this.name])
    error_message = "Every SSH key parameter must be a SecureString under the cluster key, created as \"pending\"."
  }
}

run "volumes_detach_from_a_stopped_machine" {
  command = apply

  # containerd's volume is mounted: detaching it from a running machine hangs (4abee99).
  assert {
    condition     = alltrue([for k in ["node-0", "node-1"] : aws_volume_attachment.containerd[k].stop_instance_before_detaching])
    error_message = "aws_volume_attachment.containerd must set stop_instance_before_detaching."
  }
}

run "ssm_endpoint_follows_the_partition" {
  command = apply

  # The machines' SSM helper used a hardcoded amazonaws.com host (4abee99, E-17).
  assert {
    condition     = strcontains(aws_instance.machine["jumpbox"].user_data, "https://ssm.cn-north-1.amazonaws.com.cn")
    error_message = "jumpbox: user_data must build the SSM endpoint from the partition's DNS suffix."
  }
  assert {
    condition     = strcontains(aws_instance.machine["server"].user_data, "https://ssm.cn-north-1.amazonaws.com.cn")
    error_message = "server: user_data must build the SSM endpoint from the partition's DNS suffix."
  }
  assert {
    condition     = strcontains(aws_instance.machine["node-0"].user_data, "https://ssm.cn-north-1.amazonaws.com.cn")
    error_message = "node-0: user_data must build the SSM endpoint from the partition's DNS suffix."
  }
  assert {
    condition     = strcontains(aws_instance.machine["node-1"].user_data, "https://ssm.cn-north-1.amazonaws.com.cn")
    error_message = "node-1: user_data must build the SSM endpoint from the partition's DNS suffix."
  }
}

run "key_policy_delegates_to_iam" {
  command = apply

  # GuardDuty's EBS malware scans of these volumes go through its service-linked role's IAM
  # policy, which counts only while the key policy delegates to the account (E-7).
  assert {
    condition = anytrue([for s in data.aws_iam_policy_document.kms.statement :
      s.effect != "Deny" && contains(s.actions, "kms:*") && anytrue([for p in s.principals :
    p.type == "AWS" && contains(p.identifiers, "arn:aws-cn:iam::111122223333:root")])])
    error_message = "The cluster key policy must keep its account-root (IAM delegation) statement."
  }
}

run "flow_logs_kept_30_months" {
  command = apply

  # OMB M-21-31 (FedRAMP AU-11): 12 months active and 18 cold (kthw-q85.28).
  assert {
    condition     = aws_cloudwatch_log_group.flow_logs.retention_in_days >= 913
    error_message = "Flow logs must be kept at least 30 months."
  }
}
