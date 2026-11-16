# ---- IAM: SSM Session Manager only. The S3 module adds its own bucket-scoped policy. ----
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${var.name}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "this" {
  name = "${var.name}-ec2-profile"
  role = aws_iam_role.this.name
}

# ---- Network: no SSH. Web ports only when a public domain is configured. ----
resource "aws_security_group" "this" {
  name        = "${var.name}-sg"
  description = "artcraft-cloud: no SSH, web ports only with a public domain"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name}-sg"
  }
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.this.id
  description       = "All outbound (package installs, source builds, SSM, S3)"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

locals {
  web_rules = var.open_web_ports ? {
    for pair in setproduct(var.allowed_cidrs, ["80/tcp", "443/tcp", "443/udp"]) :
    "${pair[0]}-${pair[1]}" => {
      cidr     = pair[0]
      port     = tonumber(split("/", pair[1])[0])
      protocol = split("/", pair[1])[1]
    }
  } : {}
}

resource "aws_vpc_security_group_ingress_rule" "web" {
  for_each = local.web_rules

  security_group_id = aws_security_group.this.id
  description       = "Caddy ${each.value.port}/${each.value.protocol}"
  ip_protocol       = each.value.protocol
  from_port         = each.value.port
  to_port           = each.value.port
  cidr_ipv4         = each.value.cidr
}

# MCP: only from named security groups or private ranges, never the internet.
resource "aws_vpc_security_group_ingress_rule" "mcp_sg" {
  for_each = var.mcp_port == null ? toset([]) : toset(var.mcp_allowed_security_group_ids)

  security_group_id            = aws_security_group.this.id
  description                  = "MCP from agent hosts"
  ip_protocol                  = "tcp"
  from_port                    = var.mcp_port
  to_port                      = var.mcp_port
  referenced_security_group_id = each.value
}

resource "aws_vpc_security_group_ingress_rule" "mcp_cidr" {
  for_each = var.mcp_port == null ? toset([]) : toset(var.mcp_allowed_cidrs)

  security_group_id = aws_security_group.this.id
  description       = "MCP from private range"
  ip_protocol       = "tcp"
  from_port         = var.mcp_port
  to_port           = var.mcp_port
  cidr_ipv4         = each.value
}

# ---- Instance ----
resource "aws_instance" "this" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.this.id]
  iam_instance_profile   = aws_iam_instance_profile.this.name
  user_data              = var.user_data

  # User data only runs at first boot. Changing it must not destroy a working server.
  user_data_replace_on_change = false

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
    # 2 so containers (the S3 sync sidecar) can reach the instance role.
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size_gb
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name = var.name
  }

  lifecycle {
    # A newer Ubuntu AMI or edited user data should not replace a running server.
    ignore_changes = [ami, user_data]
  }
}

resource "aws_volume_attachment" "data" {
  device_name = "/dev/sdf"
  volume_id   = var.data_volume_id
  instance_id = aws_instance.this.id
}

resource "aws_eip" "this" {
  count  = var.create_eip ? 1 : 0
  domain = "vpc"

  tags = {
    Name = var.name
  }
}

resource "aws_eip_association" "this" {
  count         = var.create_eip ? 1 : 0
  allocation_id = aws_eip.this[0].id
  instance_id   = aws_instance.this.id
}
