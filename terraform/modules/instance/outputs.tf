output "instance_id" {
  description = "EC2 instance ID."
  value       = aws_instance.this.id
}

output "role_name" {
  description = "IAM role attached to the instance."
  value       = aws_iam_role.this.name
}

output "public_ip" {
  description = "Elastic IP when one is created, otherwise the auto-assigned public IP."
  value       = var.create_eip ? aws_eip.this[0].public_ip : aws_instance.this.public_ip
}

output "private_ip" {
  description = "Private IP of the instance."
  value       = aws_instance.this.private_ip
}

output "security_group_id" {
  description = "Security group of the instance."
  value       = aws_security_group.this.id
}
