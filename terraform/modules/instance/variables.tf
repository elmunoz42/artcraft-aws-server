variable "name" {
  description = "Name prefix."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
}

variable "ami_id" {
  description = "AMI to launch (Ubuntu 24.04 x86_64)."
  type        = string
}

variable "subnet_id" {
  description = "Subnet to launch in."
  type        = string
}

variable "vpc_id" {
  description = "VPC of the subnet."
  type        = string
}

variable "root_volume_size_gb" {
  description = "Root volume size in GB."
  type        = number
}

variable "data_volume_id" {
  description = "EBS data volume to attach."
  type        = string
}

variable "open_web_ports" {
  description = "Open 80 and 443 to allowed_cidrs."
  type        = bool
}

variable "allowed_cidrs" {
  description = "CIDR blocks allowed to reach 80 and 443."
  type        = list(string)
}

variable "create_eip" {
  description = "Allocate and associate an Elastic IP."
  type        = bool
}

variable "mcp_port" {
  description = "MCP port to open to the allowed sources. Null opens nothing."
  type        = number
  default     = null
}

variable "mcp_allowed_security_group_ids" {
  description = "Security groups allowed to reach the MCP port."
  type        = list(string)
  default     = []
}

variable "mcp_allowed_cidrs" {
  description = "CIDR blocks allowed to reach the MCP port."
  type        = list(string)
  default     = []
}

variable "user_data" {
  description = "Rendered first-boot script."
  type        = string
}
