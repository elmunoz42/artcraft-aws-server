# Copy to terraform.tfvars and edit.
region   = "us-east-1"
repo_url = "https://github.com/YOUR_USER/artcraft-cloud.git"
repo_ref = "main"

# instance_type  = "t3.medium"
# volume_size_gb = 60
# create_eip     = true

# S3 backups
# enable_s3_sync = true
# bucket_name    = "my-artcraft-backups"

# Run only 5pm-9pm Pacific on weekdays (see docs/costs.md)
# enable_schedule = true

# MCP for AI agents on other instances in the same VPC (see docs/mcp.md)
# enable_mcp                     = true
# mcp_allowed_security_group_ids = ["sg-0123456789abcdef0"]

# Public HTTPS (experimental). All three are needed together.
# domain_name     = "art.example.com"
# basic_auth_user = "me"
# basic_auth_hash = "$2a$14$..."
