# The only way in (AC-17, IA-2): `aws ec2-instance-connect ssh` tunnels through
# this endpoint after IAM authorizes the caller. No public IPs, no bastion.
resource "aws_ec2_instance_connect_endpoint" "this" {
  subnet_id          = aws_subnet.private.id
  security_group_ids = [aws_security_group.eice.id]
  preserve_client_ip = false

  tags = { Name = var.cluster_name }
}
