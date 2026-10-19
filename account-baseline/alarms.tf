# CIS AWS Foundations 3.0 section 4 (Security Hub CloudWatch.1-14): a metric filter on the
# trail's log group and an alarm for each security-relevant change (AU-6, SI-4, IR-5).
# Alarms notify an SNS topic encrypted with the audit key. It has no subscriber here:
# production subscribes the security team or a SIEM (docs/exceptions.md E-13).

locals {
  cis_metric_filters = {
    unauthorized-api-calls     = "{ (($.errorCode = \"*UnauthorizedOperation\") || ($.errorCode = \"AccessDenied*\")) && ($.sourceIPAddress != \"delivery.logs.amazonaws.com\") && ($.eventName != \"HeadBucket\") }"
    console-signin-without-mfa = "{ ($.eventName = \"ConsoleLogin\") && ($.additionalEventData.MFAUsed != \"Yes\") && ($.userIdentity.type = \"IAMUser\") && ($.responseElements.ConsoleLogin = \"Success\") }"
    root-account-usage         = "{ $.userIdentity.type = \"Root\" && $.userIdentity.invokedBy NOT EXISTS && $.eventType != \"AwsServiceEvent\" }"
    iam-policy-changes         = "{ ($.eventName = DeleteGroupPolicy) || ($.eventName = DeleteRolePolicy) || ($.eventName = DeleteUserPolicy) || ($.eventName = PutGroupPolicy) || ($.eventName = PutRolePolicy) || ($.eventName = PutUserPolicy) || ($.eventName = CreatePolicy) || ($.eventName = DeletePolicy) || ($.eventName = CreatePolicyVersion) || ($.eventName = DeletePolicyVersion) || ($.eventName = AttachRolePolicy) || ($.eventName = DetachRolePolicy) || ($.eventName = AttachUserPolicy) || ($.eventName = DetachUserPolicy) || ($.eventName = AttachGroupPolicy) || ($.eventName = DetachGroupPolicy) }"
    cloudtrail-config-changes  = "{ ($.eventName = CreateTrail) || ($.eventName = UpdateTrail) || ($.eventName = DeleteTrail) || ($.eventName = StartLogging) || ($.eventName = StopLogging) }"
    console-auth-failures      = "{ ($.eventName = ConsoleLogin) && ($.errorMessage = \"Failed authentication\") }"
    cmk-disable-or-deletion    = "{ ($.eventSource = kms.amazonaws.com) && (($.eventName = DisableKey) || ($.eventName = ScheduleKeyDeletion)) }"
    s3-bucket-policy-changes   = "{ ($.eventSource = s3.amazonaws.com) && (($.eventName = PutBucketAcl) || ($.eventName = PutBucketPolicy) || ($.eventName = PutBucketCors) || ($.eventName = PutBucketLifecycle) || ($.eventName = PutBucketReplication) || ($.eventName = DeleteBucketPolicy) || ($.eventName = DeleteBucketCors) || ($.eventName = DeleteBucketLifecycle) || ($.eventName = DeleteBucketReplication)) }"
    aws-config-changes         = "{ ($.eventSource = config.amazonaws.com) && (($.eventName = StopConfigurationRecorder) || ($.eventName = DeleteDeliveryChannel) || ($.eventName = PutDeliveryChannel) || ($.eventName = PutConfigurationRecorder)) }"
    security-group-changes     = "{ ($.eventName = AuthorizeSecurityGroupIngress) || ($.eventName = AuthorizeSecurityGroupEgress) || ($.eventName = RevokeSecurityGroupIngress) || ($.eventName = RevokeSecurityGroupEgress) || ($.eventName = CreateSecurityGroup) || ($.eventName = DeleteSecurityGroup) }"
    network-acl-changes        = "{ ($.eventName = CreateNetworkAcl) || ($.eventName = CreateNetworkAclEntry) || ($.eventName = DeleteNetworkAcl) || ($.eventName = DeleteNetworkAclEntry) || ($.eventName = ReplaceNetworkAclEntry) || ($.eventName = ReplaceNetworkAclAssociation) }"
    network-gateway-changes    = "{ ($.eventName = CreateCustomerGateway) || ($.eventName = DeleteCustomerGateway) || ($.eventName = AttachInternetGateway) || ($.eventName = CreateInternetGateway) || ($.eventName = DeleteInternetGateway) || ($.eventName = DetachInternetGateway) }"
    route-table-changes        = "{ ($.eventSource = ec2.amazonaws.com) && (($.eventName = CreateRoute) || ($.eventName = CreateRouteTable) || ($.eventName = ReplaceRoute) || ($.eventName = ReplaceRouteTableAssociation) || ($.eventName = DeleteRouteTable) || ($.eventName = DeleteRoute) || ($.eventName = DisassociateRouteTable)) }"
    vpc-changes                = "{ ($.eventName = CreateVpc) || ($.eventName = DeleteVpc) || ($.eventName = ModifyVpcAttribute) || ($.eventName = AcceptVpcPeeringConnection) || ($.eventName = CreateVpcPeeringConnection) || ($.eventName = DeleteVpcPeeringConnection) || ($.eventName = RejectVpcPeeringConnection) || ($.eventName = AttachClassicLinkVpc) || ($.eventName = DetachClassicLinkVpc) || ($.eventName = DisableVpcClassicLink) || ($.eventName = EnableVpcClassicLink) }"
    # Not CIS: writes to workload/'s SSH key parameters, the root-SSH trust anchor (E-16).
    # Expected when a machine first boots or is rebuilt, and on apply and destroy.
    ssm-ssh-key-changes   = "{ ($.eventSource = ssm.amazonaws.com) && (($.eventName = PutParameter) || ($.eventName = DeleteParameter)) && ($.requestParameters.name = \"/${var.name_prefix}/*\") }"
    organizations-changes = "{ ($.eventSource = organizations.amazonaws.com) && (($.eventName = AcceptHandshake) || ($.eventName = AttachPolicy) || ($.eventName = CreateAccount) || ($.eventName = CreateOrganizationalUnit) || ($.eventName = CreatePolicy) || ($.eventName = DeclineHandshake) || ($.eventName = DeleteOrganization) || ($.eventName = DeleteOrganizationalUnit) || ($.eventName = DeletePolicy) || ($.eventName = DetachPolicy) || ($.eventName = DisablePolicyType) || ($.eventName = EnablePolicyType) || ($.eventName = InviteAccountToOrganization) || ($.eventName = LeaveOrganization) || ($.eventName = MoveAccount) || ($.eventName = RemoveAccountFromOrganization) || ($.eventName = UpdatePolicy) || ($.eventName = UpdateOrganizationalUnit)) }"
  }
}

resource "aws_sns_topic" "security_alarms" {
  name              = "${var.name_prefix}-security-alarms"
  kms_master_key_id = aws_kms_key.audit.arn
}

resource "aws_cloudwatch_log_metric_filter" "cis" {
  for_each = local.cis_metric_filters

  name           = each.key
  log_group_name = aws_cloudwatch_log_group.trail.name
  pattern        = each.value

  metric_transformation {
    name      = each.key
    namespace = "${var.name_prefix}/cis"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "cis" {
  for_each = local.cis_metric_filters

  alarm_name          = "${var.name_prefix}-${each.key}"
  alarm_description   = "CIS AWS Foundations section 4: ${each.key}"
  namespace           = "${var.name_prefix}/cis"
  metric_name         = aws_cloudwatch_log_metric_filter.cis[each.key].metric_transformation[0].name
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.security_alarms.arn]
}
