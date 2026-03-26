variable "ssh_public_key" {
  description = "SSH public key cho EC2 + Proxmox VM"
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox API token (format: USER@REALM!TOKENID=UUID)"
  type        = string
  sensitive   = true
}

variable "proxmox_ssh_password" {
  description = "Root SSH password Proxmox host"
  type        = string
  sensitive   = true
}
