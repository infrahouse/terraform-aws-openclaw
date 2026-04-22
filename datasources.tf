data "aws_region" "this" {}
data "aws_caller_identity" "this" {}

data "aws_iam_role" "instance" {
  name = module.openclaw_pod.instance_role_name
}

data "aws_subnet" "alb" {
  for_each = toset(var.alb_subnet_ids)
  id       = each.key
}

data "aws_subnet" "backend" {
  for_each = toset(var.backend_subnet_ids)
  id       = each.key
}

data "aws_kms_key" "efs_default" {
  key_id = "alias/aws/elasticfilesystem"
}

data "aws_route53_zone" "this" {
  zone_id = var.zone_id
}

data "aws_ami" "infrahouse_pro_noble" {
  most_recent = true

  filter {
    name   = "name"
    values = ["infrahouse-ubuntu-pro-noble-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }

  owners = ["303467602807"] # InfraHouse
}
