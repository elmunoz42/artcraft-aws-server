# The data volume is its own resource so it outlives the instance: replacing the instance
# re-attaches the same volume, and bootstrap finds the existing data on it.
resource "aws_ebs_volume" "data" {
  availability_zone = var.availability_zone
  size              = var.size_gb
  type              = "gp3"
  encrypted         = true

  tags = {
    Name = "${var.name}-data"
  }

  lifecycle {
    prevent_destroy = false
  }
}
