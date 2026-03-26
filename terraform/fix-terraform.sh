#!/bin/bash
# fix-terraform.sh — Chạy 1 lần: ghi đè main.tf + outputs.tf + locals.tf
# Usage: bash fix-terraform.sh

set -e
cd "$(git rev-parse --show-toplevel)/terraform" 2>/dev/null || cd terraform

echo "📁 Đang ở: $(pwd)"

# ══════════════════ locals.tf ══════════════════
cat > locals.tf << 'EOF'
locals {
  cfg          = yamldecode(file("${path.module}/../project-config.yml"))
  project_slug = replace(lower(local.cfg.project_name), "_", "-")
  vm_template_id = try(local.cfg.vm_template_id, 9000)
}
EOF
echo "✅ locals.tf"

# ══════════════════ outputs.tf ══════════════════
cat > outputs.tf << 'EOF'
output "ec2_public_ip" {
  description = "EC2 public IP — Ansible inventory"
  value       = aws_instance.web.public_ip
}

output "proxmox_vm_ip" {
  description = "Proxmox VM IP — Ansible inventory"
  value       = local.cfg.vm_ip
}

output "alb_dns" {
  description = "ALB DNS name"
  value       = aws_lb.alb.dns_name
}
EOF
echo "✅ outputs.tf"

# ══════════════════ main.tf ══════════════════
cat > main.tf << 'EOF'
resource "aws_key_pair" "deployer" {
  key_name   = "${local.project_slug}-key"
  public_key = var.ssh_public_key
}

resource "aws_vpc" "main" {
  cidr_block           = "10.10.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "${local.project_slug}-vpc" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.10.1.0/24"
  availability_zone       = "${local.cfg.aws_region}a"
  map_public_ip_on_launch = true
  tags = { Name = "${local.project_slug}-public" }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.10.2.0/24"
  availability_zone       = "${local.cfg.aws_region}b"
  map_public_ip_on_launch = true
  tags = { Name = "${local.project_slug}-public-b" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.project_slug}-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web" {
  vpc_id = aws_vpc.main.id
  name   = "${local.project_slug}-web-sg"
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 51820
    to_port     = 51820
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${local.project_slug}-web-sg" }
}

resource "aws_instance" "web" {
  ami                    = local.cfg.ami_id
  instance_type          = local.cfg.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web.id]
  key_name               = aws_key_pair.deployer.key_name
  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }
  tags = { Name = "${local.project_slug}-web" }
}

resource "aws_lb" "alb" {
  name               = "${local.project_slug}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web.id]
  subnets            = [aws_subnet.public.id, aws_subnet.public_b.id]
}

resource "aws_lb_target_group" "tg" {
  name     = "${local.project_slug}-tg"
  port     = local.cfg.flask_port
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
  health_check { path = "/" }
}

resource "aws_lb_target_group_attachment" "tg_attach" {
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.web.id
  port             = local.cfg.flask_port
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

resource "proxmox_virtual_environment_file" "cloud_init" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = local.cfg.proxmox_node
  source_raw {
    data = templatefile("${path.module}/cloud-init-basic.cfg", {
      ssh_public_key = var.ssh_public_key
    })
    file_name = "${local.project_slug}-ci.yml"
  }
}

resource "proxmox_virtual_environment_vm" "vm" {
  name      = local.cfg.vm_name
  node_name = local.cfg.proxmox_node
  vm_id     = local.cfg.vm_id

  clone {
    vm_id   = local.vm_template_id
    full    = true
    retries = 3
  }

  agent  { enabled = true }
  cpu    { cores = local.cfg.vm_cores; type = "host" }
  memory { dedicated = local.cfg.vm_memory }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = 20
  }

  network_device {
    bridge = local.cfg.vm_bridge
    model  = "virtio"
  }

  initialization {
    user_data_file_id = proxmox_virtual_environment_file.cloud_init.id
    ip_config {
      ipv4 {
        address = "${local.cfg.vm_ip}/${local.cfg.vm_cidr}"
        gateway = local.cfg.vm_gateway
      }
    }
    dns { servers = ["8.8.8.8", "1.1.1.1"] }
  }

  timeout_create = 600
  timeout_clone  = 600
}
EOF
echo "✅ main.tf"

echo ""
echo "🔍 Kiểm tra syntax..."
terraform fmt -check && echo "✅ Format OK" || terraform fmt
terraform validate && echo "✅ Validate OK"

echo ""
echo "📦 Commit & push..."
git add locals.tf main.tf outputs.tf
git commit -m "fix: rewrite main.tf locals.tf outputs.tf - fix all terraform errors"
git push origin main
echo "🚀 Done! GitHub Actions sẽ chạy lại tự động."
