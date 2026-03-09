locals {
  environment = "development"
}

module "openclaw" {
  source = "../.."
  providers = {
    aws     = aws
    aws.dns = aws.dns
  }

  environment                  = local.environment
  zone_id                      = var.zone_id
  alb_subnet_ids               = var.subnet_public_ids
  backend_subnet_ids           = var.subnet_private_ids
  alarm_emails                 = var.alarm_emails
  enable_deletion_protection   = false
  alb_access_log_force_destroy = true

  cognito_users = [
    {
      email     = "devnull@infrahouse.com"
      full_name = "Test User"
    },
  ]
}
