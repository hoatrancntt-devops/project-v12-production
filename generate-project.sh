#!/bin/bash
#====================================================================
# generate-project.sh
# Auto-generate Project Terraform & Ansible Hybrid
# Đọc từ project-config.yml → sinh toàn bộ files
# Usage: chmod +x generate-project.sh && ./generate-project.sh
#====================================================================

set -e

# ── Đọc project-config.yml ──
CONFIG="project-config.yml"
if [ ! -f "$CONFIG" ]; then
    echo "❌ Không tìm thấy $CONFIG — hãy tạo file config trước!"
    exit 1
fi

# Hàm đọc giá trị từ YAML (lightweight, không cần yq)
parse_yaml() {
    local key="$1"
    grep "^${key}:" "$CONFIG" | sed "s/^${key}:[[:space:]]*//" | sed 's/^"//' | sed 's/"$//' | sed "s/^'//" | sed "s/'$//" | sed 's/[[:space:]]*#.*//'
}

# ── Load config ──
PROJECT=$(parse_yaml project_name)
HCP_ORG=$(parse_yaml hcp_org)
HCP_WS=$(parse_yaml hcp_workspace)
AWS_REGION=$(parse_yaml aws_region)
AMI_ID=$(parse_yaml ami_id)
INSTANCE_TYPE=$(parse_yaml instance_type)
PX_API_URL=$(parse_yaml proxmox_api_url)
PX_NODE=$(parse_yaml proxmox_node)
VM_TPL=$(parse_yaml vm_template)
VM_ID=$(parse_yaml vm_id)
VM_IP=$(parse_yaml vm_ip)
VM_CIDR=$(parse_yaml vm_cidr)
VM_GW=$(parse_yaml vm_gateway)
WG_PORT=$(parse_yaml wg_listen_port)
WG_SRV=$(parse_yaml wg_server_ip)
WG_CLI=$(parse_yaml wg_client_ip)
WG_SUBNET=$(parse_yaml wg_subnet)
DB_NAME=$(parse_yaml db_name)
DB_USER=$(parse_yaml db_user)
PG_VER=$(parse_yaml pg_version)
FLASK_PORT=$(parse_yaml flask_port)
FLASK_DIR=$(parse_yaml flask_app_dir)
SSH_USER=$(parse_yaml ssh_user)
SSH_KEY=$(parse_yaml ssh_key_path)

echo "🚀 Tạo Project: $PROJECT (đọc từ $CONFIG)"
echo "=================================="
echo "   AWS Region:    $AWS_REGION"
echo "   Proxmox Node:  $PX_NODE"
echo "   VM IP:         $VM_IP/$VM_CIDR"
echo "   WireGuard:     $WG_SRV ↔ $WG_CLI"
echo "   Database:      $DB_NAME ($DB_USER)"
echo "=================================="

# ========== KIỂM TRA THƯ MỤC ==========
# Thư mục phải được tạo trước (xem phần "Tạo Cấu Trúc Thư Mục")
if [ ! -d "terraform" ] || [ ! -d "ansible" ]; then
    echo "❌ Chưa tạo cấu trúc thư mục! Hãy chạy lệnh mkdir trước."
    echo "   Xem hướng dẫn: phần 'Tạo Cấu Trúc Thư Mục' trong bài viết."
    exit 1
fi
echo "✅ Thư mục đã tồn tại — bắt đầu sinh files..."

# ========================================
# TERRAFORM FILES
# ========================================

# --- backend.tf ---
cat > "terraform/backend.tf" <<EOF
terraform {
  cloud {
    organization = "$HCP_ORG"
    workspaces {
      name = "$HCP_WS"
    }
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.38"
    }
  }
  required_version = ">= 1.6.0"
}
EOF
echo "  📄 terraform/backend.tf"

# --- providers.tf ---
cat > "terraform/providers.tf" <<'EOF'
provider "aws" {
  region = var.aws_region
}

provider "proxmox" {
  endpoint  = var.proxmox_api_url     # $PX_API_URL
  api_token = var.proxmox_api_token   # terraform@pam!tf-token=UUID
  insecure  = true
  ssh {
    agent    = false
    username = "root"
    password = var.proxmox_ssh_password
  }
}
EOF
echo "  📄 terraform/providers.tf"

# --- variables.tf (giá trị default đọc từ config) ---
cat > "terraform/variables.tf" <<EOF
variable "aws_region"           { default = "$AWS_REGION" }
variable "ami_id"               { default = "$AMI_ID" }
variable "instance_type"        { default = "$INSTANCE_TYPE" }
variable "ssh_public_key"       { description = "SSH public key for EC2 + Proxmox VM" }
variable "proxmox_api_url"      { default = "$PX_API_URL" }
variable "proxmox_api_token"    { sensitive = true }
variable "proxmox_ssh_password" { sensitive = true }
variable "proxmox_node"         { default = "$PX_NODE" }
variable "vm_template"          { default = "$VM_TPL" }
EOF
echo "  📄 terraform/variables.tf"

# --- main.tf (đọc $VM_IP, $VM_CIDR, $VM_GW từ config) ---
cat > "terraform/main.tf" <<EOF
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
  availability_zone       = "\${var.aws_region}a"
  map_public_ip_on_launch = true
  tags = { Name = "project-v11-public" }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.10.2.0/24"
  availability_zone       = "\${var.aws_region}b"
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
    data = templatefile("\${path.module}/cloud-init-basic.cfg", {
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
      ipv4 { address = "$VM_IP/$VM_CIDR"; gateway = "$VM_GW" }
    }
  }
}
EOF
echo "  📄 terraform/main.tf"

# --- cloud-init-basic.cfg ---
cat > "terraform/cloud-init-basic.cfg" <<'EOF'
#cloud-config
users:
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - ${ssh_public_key}
packages:
  - qemu-guest-agent
runcmd:
  - systemctl enable --now qemu-guest-agent
EOF
echo "  📄 terraform/cloud-init-basic.cfg"

# --- outputs.tf ---
cat > "terraform/outputs.tf" <<EOF
output "ec2_public_ip" {
  value = aws_instance.web.public_ip
}
output "proxmox_vm_ip" {
  value = "$VM_IP"
}
output "alb_dns" {
  value = aws_lb.alb.dns_name
}
EOF
echo "  📄 terraform/outputs.tf"

# ========================================
# ANSIBLE FILES
# ========================================

# --- ansible.cfg ---
cat > "ansible/ansible.cfg" <<'EOF'
[defaults]
inventory      = inventory/hosts.yml
roles_path     = roles
host_key_checking = False
timeout        = 30
remote_user    = ubuntu

[privilege_escalation]
become = True
become_method = sudo
EOF
echo "  📄 ansible/ansible.cfg"

# --- inventory/hosts.yml (đọc từ config) ---
cat > "ansible/inventory/hosts.yml" <<EOF
all:
  children:
    ec2:
      hosts:
        EC2_PUBLIC_IP:                # ← Tự động cập nhật sau terraform output
          ansible_user: $SSH_USER
          ansible_ssh_private_key_file: $SSH_KEY
    proxmox_vm:
      hosts:
        $VM_IP:
          ansible_user: $SSH_USER
          ansible_ssh_private_key_file: $SSH_KEY
EOF
echo "  📄 ansible/inventory/hosts.yml"

# --- group_vars/all/vars.yml (đọc từ config) ---
mkdir -p "ansible/group_vars/all"
cat > "ansible/group_vars/all/vars.yml" <<EOF
---
app_name: "$PROJECT"
app_port: $FLASK_PORT
app_dir: "$FLASK_DIR"
db_name: "$DB_NAME"
db_user: "$DB_USER"
db_password: "{{ vault_db_password }}"
wg_listen_port: $WG_PORT
wg_server_ip: "$WG_SRV"
wg_client_ip: "$WG_CLI"
wg_subnet: "$WG_SUBNET"
wg_private_key_ec2: "{{ vault_wg_private_key_ec2 }}"
wg_public_key_ec2: "{{ vault_wg_public_key_ec2 }}"
wg_private_key_proxmox: "{{ vault_wg_private_key_proxmox }}"
wg_public_key_proxmox: "{{ vault_wg_public_key_proxmox }}"
ec2_public_ip: "EC2_PUBLIC_IP"          # ← Cập nhật sau terraform output
pg_version: "$PG_VER"
EOF
echo "  📄 ansible/group_vars/all/vars.yml"

# --- group_vars/all/vault.yml (encrypted later) ---
cat > "ansible/group_vars/all/vault.yml" <<'EOF'
---
# MÃ HOÁ FILE NÀY: ansible-vault encrypt group_vars/vault.yml
vault_db_password: "YourSecureDbPassword123!"
vault_wg_private_key_ec2: "PASTE_EC2_WG_PRIVATE_KEY"
vault_wg_public_key_ec2: "PASTE_EC2_WG_PUBLIC_KEY"
vault_wg_private_key_proxmox: "PASTE_PROXMOX_WG_PRIVATE_KEY"
vault_wg_public_key_proxmox: "PASTE_PROXMOX_WG_PUBLIC_KEY"
EOF
echo "  📄 ansible/group_vars/all/vault.yml"

# --- site.yml ---
cat > "ansible/site.yml" <<'EOF'
---
- import_playbook: ec2.yml
- import_playbook: proxmox.yml
EOF
echo "  📄 ansible/site.yml"

# --- ec2.yml ---
cat > "ansible/ec2.yml" <<'EOF'
---
- name: Configure EC2 Web Server
  hosts: ec2
  become: true
  vars:
    wg_role: "server"
    wg_address: "10.0.0.1/24"
    wg_listen_port: 51820
    wg_peer_public_key: "{{ wg_public_key_proxmox }}"
    wg_peer_allowed_ips: "10.0.0.2/32"
  roles:
    - common
    - wireguard
    - flask_app
EOF
echo "  📄 ansible/ec2.yml"

# --- proxmox.yml ---
cat > "ansible/proxmox.yml" <<'EOF'
---
- name: Configure Proxmox VM Database
  hosts: proxmox_vm
  become: true
  vars:
    wg_role: "client"
    wg_address: "10.0.0.2/24"
    wg_peer_public_key: "{{ wg_public_key_ec2 }}"
    wg_peer_allowed_ips: "10.0.0.1/32"
    wg_peer_endpoint: "{{ ec2_public_ip }}:51820"
  roles:
    - common
    - wireguard
    - postgresql
EOF
echo "  📄 ansible/proxmox.yml"

# --- Role: common ---
cat > "ansible/roles/common/tasks/main.yml" <<'EOF'
---
- name: Update apt cache
  apt:
    update_cache: yes
    cache_valid_time: 3600

- name: Install common packages
  apt:
    name:
      - curl
      - wget
      - net-tools
      - htop
      - vim
    state: present
EOF
echo "  📄 ansible/roles/common/tasks/main.yml"

# --- Role: wireguard ---
cat > "ansible/roles/wireguard/tasks/main.yml" <<'EOF'
---
- name: Install WireGuard
  apt:
    name: wireguard
    state: present

- name: Deploy WireGuard config
  template:
    src: wg0.conf.j2
    dest: /etc/wireguard/wg0.conf
    mode: '0600'
  notify: restart wireguard

- name: Enable and start WireGuard
  systemd:
    name: wg-quick@wg0
    enabled: yes
    state: started

- name: Add cron for auto-reconnect (client only)
  cron:
    name: "wireguard-reconnect"
    minute: "*/5"
    job: "/usr/bin/ping -c 1 10.0.0.1 > /dev/null 2>&1 || /usr/bin/systemctl restart wg-quick@wg0"
  when: wg_role == "client"
EOF
echo "  📄 ansible/roles/wireguard/tasks/main.yml"

cat > "ansible/roles/wireguard/handlers/main.yml" <<'EOF'
---
- name: restart wireguard
  systemd:
    name: wg-quick@wg0
    state: restarted
EOF
echo "  📄 ansible/roles/wireguard/handlers/main.yml"

# --- Jinja2 Template: wg0.conf.j2 ---
cat > "ansible/roles/wireguard/templates/wg0.conf.j2" <<'EOF'
[Interface]
PrivateKey = {% if wg_role == "server" %}{{ wg_private_key_ec2 }}{% else %}{{ wg_private_key_proxmox }}{% endif %}

Address = {{ wg_address }}
{% if wg_role == "server" %}
ListenPort = {{ wg_listen_port }}
{% endif %}

[Peer]
PublicKey = {{ wg_peer_public_key }}
AllowedIPs = {{ wg_peer_allowed_ips }}
{% if wg_role == "client" %}
Endpoint = {{ wg_peer_endpoint }}
PersistentKeepalive = 25
{% endif %}
EOF
echo "  📄 ansible/roles/wireguard/templates/wg0.conf.j2"

# --- Role: flask_app ---
cat > "ansible/roles/flask_app/tasks/main.yml" <<'EOF'
---
- name: Install Python & pip
  apt:
    name:
      - python3
      - python3-pip
      - python3-venv
    state: present

- name: Create app directory
  file:
    path: /opt/flask-app
    state: directory
    owner: ubuntu
    mode: '0755'

- name: Create virtual environment
  command: python3 -m venv /opt/flask-app/venv
  args:
    creates: /opt/flask-app/venv

- name: Install Flask & psycopg2
  pip:
    name:
      - flask
      - psycopg2-binary
    virtualenv: /opt/flask-app/venv

- name: Deploy app.py
  template:
    src: app.py.j2
    dest: /opt/flask-app/app.py
    owner: ubuntu
  notify: restart flask

- name: Deploy systemd service
  template:
    src: flask-app.service.j2
    dest: /etc/systemd/system/flask-app.service
  notify: restart flask

- name: Enable and start Flask service
  systemd:
    name: flask-app
    enabled: yes
    state: started
    daemon_reload: yes
EOF
echo "  📄 ansible/roles/flask_app/tasks/main.yml"

cat > "ansible/roles/flask_app/handlers/main.yml" <<'EOF'
---
- name: restart flask
  systemd:
    name: flask-app
    state: restarted
    daemon_reload: yes
EOF
echo "  📄 ansible/roles/flask_app/handlers/main.yml"

cat > "ansible/roles/flask_app/templates/app.py.j2" <<'EOF'
from flask import Flask, request, render_template_string
import psycopg2

app = Flask(__name__)

def get_db():
    return psycopg2.connect(
        host="10.0.0.2",
        database="{{ db_name }}",
        user="{{ db_user }}",
        password="{{ db_password }}"
    )

HTML = """
<!DOCTYPE html>
<html><head><title>{{ app_name }}</title>
<style>body{font-family:Arial;max-width:600px;margin:40px auto;padding:20px}
input,button{padding:8px;margin:4px}table{width:100%;border-collapse:collapse}
td,th{border:1px solid #ddd;padding:8px}</style></head>
<body><h1>{{ app_name }} - Hybrid Cloud</h1>
<form method="POST"><input name="entry" placeholder="Type something...">
<button type="submit">Add</button></form>
<table><tr><th>ID</th><th>Content</th><th>Created</th></tr>
{% for e in entries %}<tr><td>{{e[0]}}</td><td>{{e[1]}}</td><td>{{e[2]}}</td></tr>{% endfor %}
</table></body></html>"""

@app.route("/", methods=["GET","POST"])
def index():
    db = get_db()
    cur = db.cursor()
    if request.method == "POST":
        cur.execute("INSERT INTO entries (content) VALUES (%s)", (request.form["entry"],))
        db.commit()
    cur.execute("SELECT * FROM entries ORDER BY id DESC")
    entries = cur.fetchall()
    cur.close(); db.close()
    return render_template_string(HTML, entries=entries)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port={{ app_port }})
EOF
echo "  📄 ansible/roles/flask_app/templates/app.py.j2"

cat > "ansible/roles/flask_app/templates/flask-app.service.j2" <<'EOF'
[Unit]
Description=Flask App - {{ app_name }}
After=network.target

[Service]
User=ubuntu
WorkingDirectory=/opt/flask-app
ExecStart=/opt/flask-app/venv/bin/python app.py
Restart=always
RestartSec=5
Environment=FLASK_ENV=production

[Install]
WantedBy=multi-user.target
EOF
echo "  📄 ansible/roles/flask_app/templates/flask-app.service.j2"

# --- Role: postgresql ---
cat > "ansible/roles/postgresql/tasks/main.yml" <<'EOF'
---
- name: Install PostgreSQL
  apt:
    name:
      - postgresql
      - postgresql-contrib
      - libpq-dev
      - python3-psycopg2
    state: present

- name: Start and enable PostgreSQL
  systemd:
    name: postgresql
    enabled: yes
    state: started

- name: Create database
  become_user: postgres
  community.postgresql.postgresql_db:
    name: "{{ db_name }}"
    state: present

- name: Create database user
  become_user: postgres
  community.postgresql.postgresql_user:
    name: "{{ db_user }}"
    password: "{{ db_password }}"
    db: "{{ db_name }}"
    priv: "ALL"
    state: present

- name: Create entries table
  become_user: postgres
  community.postgresql.postgresql_query:
    db: "{{ db_name }}"
    query: |
      CREATE TABLE IF NOT EXISTS entries (
        id SERIAL PRIMARY KEY,
        content TEXT NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );

- name: Allow remote connections (pg_hba.conf)
  lineinfile:
    path: /etc/postgresql/14/main/pg_hba.conf
    line: "host    {{ db_name }}    {{ db_user }}    10.0.0.0/24    md5"
    insertafter: "# IPv4 local connections"
  notify: restart postgresql

- name: Listen on all interfaces
  lineinfile:
    path: /etc/postgresql/14/main/postgresql.conf
    regexp: "^#?listen_addresses"
    line: "listen_addresses = '*'"
  notify: restart postgresql
EOF
echo "  📄 ansible/roles/postgresql/tasks/main.yml"

cat > "ansible/roles/postgresql/handlers/main.yml" <<'EOF'
---
- name: restart postgresql
  systemd:
    name: postgresql
    state: restarted
EOF
echo "  📄 ansible/roles/postgresql/handlers/main.yml"

# --- .gitignore ---
cat > ".gitignore" <<'EOF'
# Terraform
.terraform/
*.tfstate
*.tfstate.backup
*.tfvars

# Ansible
*.retry
ansible/group_vars/all/vault.yml

# Keys
*.pem
privatekey
EOF
echo "  📄 .gitignore"

# ========== HOÀN TẤT ==========
echo ""
echo "=================================="
echo "✅ HOÀN TẤT! Cấu trúc project:"
echo "=================================="
find "$PROJECT" -type f | sort | head -40

echo ""
echo "📋 Config đã được đọc từ: $CONFIG"
echo "   Tất cả non-secret values đã tự động điền vào Terraform + Ansible files."
echo ""
echo "📋 BƯỚC TIẾP THEO (chỉ còn secrets):"
echo "  1. Sửa WG keys + password trong ansible/group_vars/all/vault.yml"
echo "  2. Mã hóa vault: ansible-vault encrypt $PROJECT/ansible/group_vars/all/vault.yml"
echo "  3. Nhập 3 sensitive vars trên HCP: proxmox_api_token, proxmox_ssh_password, ssh_public_key"
echo "  4. Push code lên GitHub → HCP Terraform tự động plan → CTO duyệt"
echo "  5. Sau khi apply: cập nhật EC2 IP vào ansible/inventory/hosts.yml"
echo "  6. cd $PROJECT/ansible && ansible-playbook site.yml --ask-vault-pass"
