output "volume_id" {
  description = "ID of the data volume."
  value       = aws_ebs_volume.data.id
}
