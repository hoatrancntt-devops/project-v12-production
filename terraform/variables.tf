# ✅ ĐÚNG
variable "aws_region" {
  default = "ap-southeast-1"
}

variable "ami_id" {
  default = "ami-0672fd5b9210aa093"
}

variable "instance_type" {
  default = "t2.micro"
}

variable "ssh_public_key" {
  description = "SSH public key for EC2 + Proxmox VM"
  type        = string
}
variable "proxmox_api_url" {
  default = "https://172.199.10.165:8006"
}

variable "proxmox_api_token" {           # ← đổi từ proxmox_api_token_id
  description = "Proxmox API token (format: USER@REALM!TOKENID=UUID)"
  type        = string
  sensitive   = true
}

variable "proxmox_ssh_password" {        # ← đổi từ proxmox_api_token_secret
  description = "Root SSH password for Proxmox host"
  type        = string
  sensitive   = true
}

variable "proxmox_node" {
  default = "promox02"
}

variable "vm_template" {
  default = "ubuntu-cloud-init"
}
