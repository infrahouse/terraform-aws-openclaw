output "url" {
  description = "OpenClaw dashboard URL."
  value       = "https://${local.fqdn}"
}

output "asg_name" {
  description = "Auto Scaling Group name."
  value       = module.openclaw_pod.asg_name
}

output "cognito_user_pool_id" {
  description = "Cognito user pool ID. Create users with aws cognito-idp admin-create-user."
  value       = aws_cognito_user_pool.this.id
}

output "cognito_domain_url" {
  description = "Cognito hosted UI domain URL for debugging authentication."
  value       = "https://${aws_cognito_user_pool_domain.this.domain}.auth.${data.aws_region.this.name}.amazoncognito.com"
}

output "secret_arn" {
  description = "Secrets Manager ARN where LLM API keys are stored."
  value       = module.api_keys.secret_arn
}

output "secret_name" {
  description = "Secrets Manager secret name where LLM API keys are stored."
  value       = module.api_keys.secret_name
}

output "alb_dns_name" {
  description = "ALB DNS name."
  value       = module.openclaw_pod.load_balancer_dns_name
}

output "alb_arn" {
  description = "ALB ARN."
  value       = module.openclaw_pod.load_balancer_arn
}

output "instance_role_name" {
  description = "IAM role name attached to the EC2 instances, for adding extra policies."
  value       = module.openclaw_pod.instance_role_name
}

output "backend_security_group_id" {
  description = "Security group ID of the backend EC2 instances."
  value       = module.openclaw_pod.backend_security_group_id
}

output "efs_file_system_id" {
  description = "EFS file system ID for persistent OpenClaw data."
  value       = aws_efs_file_system.this.id
}

output "cloudwatch_log_group_name" {
  description = "CloudWatch log group name for application logs."
  value       = aws_cloudwatch_log_group.this.name
}

output "ssh_private_key" {
  description = "Auto-generated SSH private key. Null when var.key_name is provided."
  value       = var.key_name == null ? tls_private_key.this[0].private_key_openssh : null
  sensitive   = true
}
