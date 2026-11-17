variable "name" {
  description = "Name prefix."
  type        = string
}

variable "instance_id" {
  description = "Instance to start and stop."
  type        = string
}

variable "timezone" {
  description = "IANA time zone the cron expressions are read in."
  type        = string
}

variable "start_cron" {
  description = "EventBridge cron fields for starting the instance."
  type        = string
}

variable "stop_cron" {
  description = "EventBridge cron fields for stopping the instance."
  type        = string
}
