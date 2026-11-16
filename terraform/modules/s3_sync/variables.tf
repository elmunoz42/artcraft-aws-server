variable "name" {
  description = "Name prefix."
  type        = string
}

variable "bucket_name" {
  description = "Bucket name. Null generates a unique name from var.name."
  type        = string
  default     = null
}

variable "prefix" {
  description = "Key prefix used by the sync sidecar."
  type        = string
}

variable "role_name" {
  description = "Instance IAM role that gets access to the bucket."
  type        = string
}

variable "noncurrent_version_transition_days" {
  description = "Days after which old versions move to Glacier Instant Retrieval."
  type        = number
}

variable "noncurrent_version_expiration_days" {
  description = "Days after which old versions are deleted. 0 keeps them forever."
  type        = number
}
