module "openclaw" {
  source  = "registry.infrahouse.com/infrahouse/openclaw/aws"
  version = "0.3.0"
  providers = {
    aws     = aws
    aws.dns = aws
  }

  environment        = var.environment
  zone_id            = var.zone_id
  alb_subnet_ids     = var.alb_subnet_ids
  backend_subnet_ids = var.backend_subnet_ids
  alarm_emails       = var.alarm_emails

  cognito_users = [
    {
      email     = "admin@example.com"
      full_name = "Admin User"
    },
  ]
}