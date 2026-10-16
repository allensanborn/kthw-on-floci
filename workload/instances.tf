# Dedicated containerd volume per worker (spike 02): keeps container data off
# the root volume, and gives containerd's overlayfs snapshotter a real
# filesystem on floci.
resource "aws_ebs_volume" "containerd" {
  for_each = { for k, v in local.machines : k => v if v.data_volume }

  availability_zone = local.az
  size              = 20
  type              = "gp3"
  encrypted         = true
  kms_key_id        = aws_kms_key.this.arn

  tags = { Name = "${var.cluster_name}-${each.key}-containerd" }
}

resource "aws_instance" "machine" {
  for_each = local.machines

  ami                    = data.aws_ami.debian.id
  instance_type          = each.value.type
  subnet_id              = aws_subnet.private.id
  private_ip             = each.value.ip
  vpc_security_group_ids = [each.key == "jumpbox" ? aws_security_group.jumpbox.id : aws_security_group.cluster.id]
  iam_instance_profile   = aws_iam_instance_profile.machine[each.key].name
  # Lab 11 routes pod subnets through node IPs, which AWS drops unless the
  # node may forward traffic not addressed to itself.
  source_dest_check = each.key == "jumpbox" || each.key == "server"
  monitoring        = true
  ebs_optimized     = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    encrypted             = true
    kms_key_id            = aws_kms_key.this.arn
    delete_on_termination = true
  }

  user_data_replace_on_change = true
  user_data = templatefile("${path.module}/templates/user-data.sh.tftpl", {
    name                 = each.key
    region               = var.region
    ssm_prefix           = local.ssm_prefix
    members              = { for k, v in local.cluster_members : k => v.ip }
    machines_txt         = local.machines_txt
    containerd_volume_id = each.value.data_volume ? aws_ebs_volume.containerd[each.key].id : ""
  })

  tags = { Name = "${var.cluster_name}-${each.key}" }
}

resource "aws_volume_attachment" "containerd" {
  for_each = aws_ebs_volume.containerd

  device_name = "/dev/xvdf"
  volume_id   = each.value.id
  instance_id = aws_instance.machine[each.key].id
}
