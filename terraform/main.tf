# ============ AWS ============
resource "aws_key_pair" "deployer" {
  key_name   = "project-v11-key"
  public_key = var.ssh_public_key
}

resource "aws_vpc" "main" {
  cidr_block           = "10.10.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "project-v11-vpc" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.10.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true
  tags = { Name = "project-v11-public" }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.10.2.0/24"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true
  tags = { Name = "project-v11-public-b" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "project-v11-igw" }
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
  name   = "project-v11-web-sg"

  ingress { from_port = 22;    to_port = 22;    protocol = "tcp"; cidr_blocks = ["0.0.0.0/0"] }
  ingress { from_port = 80;    to_port = 80;    protocol = "tcp"; cidr_blocks = ["0.0.0.0/0"] }
  ingress { from_port = 5000;  to_port = 5000;  protocol = "tcp"; cidr_blocks = ["0.0.0.0/0"] }
  ingress { from_port = 51820; to_port = 51820; protocol = "udp"; cidr_blocks = ["0.0.0.0/0"] }
  egress  { from_port = 0;     to_port = 0;     protocol = "-1";  cidr_blocks = ["0.0.0.0/0"] }

  tags = { Name = "project-v11-web-sg" }
}

resource "aws_instance" "web" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web.id]
  key_name               = aws_key_pair.deployer.key_name
  # Không có user-data — Ansible sẽ cấu hình sau
  tags = { Name = "project-v11-web" }
}

# ============ ALB ============
resource "aws_lb" "alb" {
  name               = "project-v11-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web.id]
  subnets            = [aws_subnet.public.id, aws_subnet.public_b.id]
}

resource "aws_lb_target_group" "tg" {
  name     = "project-v11-tg"
  port     = 5000
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
  health_check { path = "/" }
}

resource "aws_lb_target_group_attachment" "tg_attach" {
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.web.id
  port             = 5000
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

# ============ PROXMOX VM ============
resource "proxmox_virtual_environment_file" "cloud_init" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.proxmox_node

  source_raw {
    data = templatefile("${path.module}/cloud-init-basic.cfg", {
      ssh_public_key = var.ssh_public_key
    })
    file_name = "project-v11-ci.yml"
  }
}

resource "proxmox_virtual_environment_vm" "db" {
  name      = "project-v11-db"
  node_name = var.proxmox_node
  vm_id     = 1100

  clone { vm_id = 9000 }

  agent { enabled = true; timeout = "5m" }

  cpu    { cores = 2 }
  memory { dedicated = 2048 }

  network_device { bridge = "vmbr0" }

  initialization {
    user_data_file_id = proxmox_virtual_environment_file.cloud_init.id
    ip_config {
      ipv4 { address = "172.199.10.180"/24""; gateway = "172.199.10.1"" }
    }
  }
}
