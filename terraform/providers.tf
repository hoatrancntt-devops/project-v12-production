provider "aws" {
  region = var.aws_region
}

provider "proxmox" {
  endpoint  = local.cfg.proxmox_api_url
  api_token = var.proxmox_api_token        # ← tên mới
  insecure  = true
  ssh {
    agent    = false
    username = "root"
    password = var.proxmox_ssh_password    # ← tên mới
  }
}
