provider "aws" {
  region = var.aws_region
}

provider "proxmox" {
  endpoint  = local.cfg.proxmox_api_url  # ← từ project-config.yml
  api_token = var.proxmox_api_token   # terraform@pam!tf-token=UUID
  insecure  = true
  ssh {
    agent    = false
    username = "root"
    password = var.proxmox_ssh_password
  }
}
