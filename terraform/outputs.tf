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
