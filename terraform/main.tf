provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.name
      ManagedBy = "terraform"
    }
  }
}

locals {
  data_dir     = "/data/artcraft"
  public_https = var.domain_name != ""

  bootstrap_flags = join(" ", compact([
    "--install-docker",
    "--docker-data-root",
    var.swap_gb > 0 ? "--swap-gb ${var.swap_gb}" : "",
    var.auto_build ? "--build --start" : "",
  ]))
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

data "aws_subnet" "selected" {
  id = coalesce(var.subnet_id, sort(data.aws_subnets.default.ids)[0])
}

data "aws_ssm_parameter" "ubuntu" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

module "storage" {
  source = "./modules/storage"

  name              = var.name
  availability_zone = data.aws_subnet.selected.availability_zone
  size_gb           = var.volume_size_gb
}

module "s3_sync" {
  source = "./modules/s3_sync"
  count  = var.enable_s3_sync ? 1 : 0

  name                               = var.name
  bucket_name                        = var.bucket_name
  prefix                             = var.s3_prefix
  role_name                          = module.instance.role_name
  noncurrent_version_transition_days = var.noncurrent_version_transition_days
  noncurrent_version_expiration_days = var.noncurrent_version_expiration_days
}

module "schedule" {
  source = "./modules/schedule"
  count  = var.enable_schedule ? 1 : 0

  name        = var.name
  instance_id = module.instance.instance_id
  timezone    = var.schedule_timezone
  start_cron  = var.schedule_start_cron
  stop_cron   = var.schedule_stop_cron
}

module "instance" {
  source = "./modules/instance"

  name                = var.name
  instance_type       = var.instance_type
  ami_id              = nonsensitive(data.aws_ssm_parameter.ubuntu.value)
  subnet_id           = data.aws_subnet.selected.id
  vpc_id              = data.aws_subnet.selected.vpc_id
  root_volume_size_gb = var.root_volume_size_gb
  data_volume_id      = module.storage.volume_id
  open_web_ports      = local.public_https
  allowed_cidrs       = var.allowed_cidrs
  create_eip          = var.create_eip

  mcp_port                       = var.enable_mcp ? var.mcp_port : null
  mcp_allowed_security_group_ids = var.mcp_allowed_security_group_ids
  mcp_allowed_cidrs              = var.mcp_allowed_cidrs

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    data_volume_id        = module.storage.volume_id
    data_dir              = local.data_dir
    region                = var.region
    repo_url              = var.repo_url
    repo_ref              = var.repo_ref
    bootstrap_flags       = local.bootstrap_flags
    s3_sync_enabled       = var.enable_s3_sync
    s3_bucket             = var.enable_s3_sync ? module.s3_sync[0].bucket_name : ""
    s3_prefix             = var.s3_prefix
    sync_interval_seconds = var.sync_interval_seconds
    domain_name           = var.domain_name
    basic_auth_user       = var.basic_auth_user
    basic_auth_hash       = var.basic_auth_hash
    mcp_enabled           = var.enable_mcp
    mcp_port              = var.mcp_port
  })
}
