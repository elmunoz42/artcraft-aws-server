variable "name" {
  description = "Name prefix."
  type        = string
}

variable "availability_zone" {
  description = "Availability zone. Must match the instance's subnet."
  type        = string
}

variable "size_gb" {
  description = "Volume size in GB."
  type        = number
}
