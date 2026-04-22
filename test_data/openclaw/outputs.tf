output "url" {
  description = "OpenClaw dashboard URL"
  value       = module.openclaw.url
}

output "asg_name" {
  description = "Auto Scaling Group name"
  value       = module.openclaw.asg_name
}

output "cognito_user_pool_id" {
  description = "Cognito user pool ID"
  value       = module.openclaw.cognito_user_pool_id
}

output "cognito_domain_url" {
  description = "Cognito hosted UI domain URL"
  value       = module.openclaw.cognito_domain_url
}

output "secret_arn" {
  description = "Secrets Manager ARN for API keys"
  value       = module.openclaw.secret_arn
}

output "secret_name" {
  description = "Secrets Manager secret name for API keys"
  value       = module.openclaw.secret_name
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = module.openclaw.alb_dns_name
}

output "alb_arn" {
  description = "ALB ARN"
  value       = module.openclaw.alb_arn
}

output "instance_role_name" {
  description = "IAM role name attached to EC2 instances"
  value       = module.openclaw.instance_role_name
}

output "backend_security_group_id" {
  description = "Security group ID of backend EC2 instances"
  value       = module.openclaw.backend_security_group_id
}

output "efs_file_system_id" {
  description = "EFS file system ID"
  value       = module.openclaw.efs_file_system_id
}

output "cloudwatch_log_group_name" {
  description = "CloudWatch log group name"
  value       = module.openclaw.cloudwatch_log_group_name
}
