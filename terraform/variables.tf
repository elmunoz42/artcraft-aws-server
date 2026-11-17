variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Name prefix and Project tag for every resource."
  type        = string
  default     = "artcraft-cloud"
}

variable "instance_type" {
  description = "EC2 instance type. t3.medium (4 GB) is the smallest that can run the stack. The first boot compiles ArtCraft from source and upstream asks for 4 vCPU and 8 GB RAM plus 8 GB swap for that; see docs/costs.md."
  type        = string
  default     = "t3.medium"
}

variable "volume_size_gb" {
  description = "Size of the EBS data volume in GB. Holds Docker's data-root (images, build cache, volumes) and backups. The build alone needs about 40 GB free."
  type        = number
  default     = 60

  validation {
    condition     = var.volume_size_gb >= 40
    error_message = "volume_size_gb must be at least 40: the source build does not fit in less."
  }
}

variable "root_volume_size_gb" {
  description = "Size of the root volume in GB."
  type        = number
  default     = 20
}

variable "swap_gb" {
  description = "Swap file size in GB created at first boot, on the data volume. 0 disables. On a 4 GB instance the build leans on this heavily."
  type        = number
  default     = 12
}

variable "subnet_id" {
  description = "Public subnet to launch in. Null uses the first default subnet of the default VPC."
  type        = string
  default     = null
}

variable "domain_name" {
  description = "Optional public hostname. Empty keeps the instance closed to the internet (reach it with SSM port forwarding). Setting it opens 80/443 and enables the experimental Caddy add-on."
  type        = string
  default     = ""

  validation {
    condition     = var.domain_name == "" || (var.basic_auth_user != "" && var.basic_auth_hash != "")
    error_message = "domain_name is set, so basic_auth_user and basic_auth_hash must be set too. ArtCraft's own signup is open to anyone who can reach it."
  }
}

variable "allowed_cidrs" {
  description = "CIDR blocks allowed to reach ports 80 and 443. Only used when domain_name is set. Port 80 must be reachable from the internet for Let's Encrypt HTTP validation."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "basic_auth_user" {
  description = "Username for the sign-in prompt in front of ArtCraft. Required when domain_name is set."
  type        = string
  default     = ""
}

variable "basic_auth_hash" {
  description = "bcrypt hash for the sign-in prompt, from `caddy hash-password`. Required when domain_name is set. It is written to instance user data, which anyone with ec2:DescribeInstanceAttribute can read."
  type        = string
  default     = ""
  sensitive   = true
}

variable "create_eip" {
  description = "Allocate an Elastic IP. Set false if the account is at its Elastic IP quota; the instance then has a public IP that changes on stop/start."
  type        = bool
  default     = true
}

variable "enable_s3_sync" {
  description = "Create an S3 bucket and sync backups to it."
  type        = bool
  default     = false
}

variable "bucket_name" {
  description = "Name of the backup bucket when enable_s3_sync is true. Null generates a unique name from var.name."
  type        = string
  default     = null
}

variable "s3_prefix" {
  description = "Key prefix inside the bucket."
  type        = string
  default     = "backups"
}

variable "sync_interval_seconds" {
  description = "Seconds between S3 sync runs."
  type        = number
  default     = 300
}

variable "noncurrent_version_transition_days" {
  description = "Days after which old object versions move to Glacier Instant Retrieval."
  type        = number
  default     = 30
}

variable "noncurrent_version_expiration_days" {
  description = "Days after which old object versions are deleted. 0 keeps them forever."
  type        = number
  default     = 365
}

variable "enable_schedule" {
  description = "Run the instance only during set hours to save money. See docs/costs.md."
  type        = bool
  default     = false
}

variable "schedule_timezone" {
  description = "IANA time zone for the schedule."
  type        = string
  default     = "America/Los_Angeles"
}

variable "schedule_start_cron" {
  description = "When to start the instance, as EventBridge cron fields (minutes hours day-of-month month day-of-week year). Default: 5pm on weekdays."
  type        = string
  default     = "0 17 ? * MON-FRI *"
}

variable "schedule_stop_cron" {
  description = "When to stop the instance. Default: 9pm on weekdays."
  type        = string
  default     = "0 21 ? * MON-FRI *"
}

variable "enable_mcp" {
  description = "Run the MCP add-on so AI agents can drive the headless Craft apps. See docs/mcp.md."
  type        = bool
  default     = false
}

variable "mcp_port" {
  description = "Port of the MCP endpoint."
  type        = number
  default     = 8811
}

variable "mcp_allowed_security_group_ids" {
  description = "Security groups whose instances may reach the MCP port (agent hosts in the same VPC)."
  type        = list(string)
  default     = []
}

variable "mcp_allowed_cidrs" {
  description = "CIDR blocks that may reach the MCP port. Use private ranges; the endpoint is plain HTTP with a bearer token."
  type        = list(string)
  default     = []

  validation {
    condition     = !contains(var.mcp_allowed_cidrs, "0.0.0.0/0")
    error_message = "The MCP port must not be open to the internet. It lets its caller run commands on the instance."
  }
}

variable "repo_url" {
  description = "Git URL of this repository (your fork). The instance clones it at first boot."
  type        = string
}

variable "repo_ref" {
  description = "Branch, tag or commit of repo_url to check out. Pin a commit for reproducible instances."
  type        = string
  default     = "main"
}

variable "auto_build" {
  description = "Build and start the stack at first boot. The build can take an hour. False only prepares the host."
  type        = bool
  default     = true
}
