# Run the instance only during set hours: EventBridge Scheduler starts and stops it.
# A stopped instance costs nothing for compute; volumes and the Elastic IP still bill.
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

data "aws_iam_policy_document" "start_stop" {
  statement {
    actions   = ["ec2:StartInstances", "ec2:StopInstances"]
    resources = ["arn:aws:ec2:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:instance/${var.instance_id}"]
  }
}

resource "aws_iam_role" "this" {
  name               = "${var.name}-schedule-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_role_policy" "this" {
  name   = "start-stop-${var.name}"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.start_stop.json
}

locals {
  actions = {
    start = { cron = var.start_cron, api = "startInstances" }
    stop  = { cron = var.stop_cron, api = "stopInstances" }
  }
}

resource "aws_scheduler_schedule" "this" {
  for_each = local.actions

  name                         = "${var.name}-${each.key}"
  description                  = "${title(each.key)} ${var.name} on a schedule"
  schedule_expression          = "cron(${each.value.cron})"
  schedule_expression_timezone = var.timezone
  state                        = "ENABLED"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ec2:${each.value.api}"
    role_arn = aws_iam_role.this.arn
    input    = jsonencode({ InstanceIds = [var.instance_id] })

    retry_policy {
      maximum_retry_attempts = 3
    }
  }
}
