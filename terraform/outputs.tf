output "ec2_public_ip" {
  value = aws_instance.web.public_ip
}
output "proxmox_vm_ip" {
  value = "172.199.10.180""
}
output "alb_dns" {
  value = aws_lb.alb.dns_name
}
