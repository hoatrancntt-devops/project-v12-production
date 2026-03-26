# ← Chỉ khai báo 3 biến SENSITIVE — còn lại đọc từ local.cfg
variable "ssh_public_key"       { description = "SSH public key for EC2 + Proxmox VM" }
variable "proxmox_api_token"    { sensitive = true }  # ← HCP Variables
variable "proxmox_ssh_password" { sensitive = true }
variable "proxmox_node"         { default = "promox02"" }
variable "vm_template"          { default = "ubuntu-cloud-init"" }
