output "jumpbox_instance_id" {
  description = "The jumpbox instance. Connect with the command in `connect`."
  value       = aws_instance.machine["jumpbox"].id
}

output "connect" {
  description = "Open a shell on the jumpbox through the EC2 Instance Connect Endpoint."
  value       = "aws ec2-instance-connect ssh --region ${var.region} --instance-id ${aws_instance.machine["jumpbox"].id} --os-user admin --connection-type eice"
}

output "machines_txt" {
  description = "KTHW lab 3's machine database (also written to /root/machines.txt on the jumpbox)."
  value       = local.machines_txt
}

output "instance_connect_endpoint_id" {
  value = aws_ec2_instance_connect_endpoint.this.id
}
