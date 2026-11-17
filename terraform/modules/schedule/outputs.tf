output "schedule_names" {
  description = "Names of the start and stop schedules."
  value       = [for s in aws_scheduler_schedule.this : s.name]
}
