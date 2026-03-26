output "ec2_public_ip" {
  description = "EC2 public IP"
  value       = aws_instance.web.public_ip
}

output "proxmox_vm_ip" {
  description = "Proxmox VM IP"
  value       = local.cfg.vm_ip
}

output "alb_dns" {
  description = "ALB DNS"
  value       = aws_lb.alb.dns_name
}
