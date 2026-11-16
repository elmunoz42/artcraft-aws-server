output "public_url" {
  description = "Where to open ArtCraft."
  value       = var.domain_name != "" ? "https://${var.domain_name}" : "http://localhost:4201 (after running ssm_port_forward_command)"
}

output "instance_id" {
  description = "EC2 instance ID."
  value       = module.instance.instance_id
}

output "public_ip" {
  description = "Public IP of the instance. Point your domain's A record here."
  value       = module.instance.public_ip
}

output "bucket_name" {
  description = "Backup bucket, or null when S3 sync is off."
  value       = var.enable_s3_sync ? module.s3_sync[0].bucket_name : null
}

output "data_volume_id" {
  description = "EBS data volume. It is kept when the instance is replaced."
  value       = module.storage.volume_id
}

output "ssm_port_forward_command" {
  description = "Run on your computer (needs the AWS CLI Session Manager plugin), then open http://localhost:4201."
  value       = "aws ssm start-session --region ${var.region} --target ${module.instance.instance_id} --document-name AWS-StartPortForwardingSession --parameters portNumber=4201,localPortNumber=4201"
}

output "ssm_shell_command" {
  description = "Shell on the instance without SSH."
  value       = "aws ssm start-session --region ${var.region} --target ${module.instance.instance_id}"
}
