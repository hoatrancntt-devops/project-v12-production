provider "aws" {
  region = var.aws_region
}

provider "proxmox" {
  endpoint  = var.proxmox_api_url   # $PX_API_URL
  api_token = var.proxmox_api_token # terraform@pam!tf-token=UUID
  insecure  = true
  ssh {
    agent    = false
    username = "root"
    password = var.proxmox_ssh_password
  }
}
