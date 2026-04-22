output "url" {
  description = "OpenClaw dashboard URL."
  value       = module.openclaw.url
}

output "secret_arn" {
  description = "Secrets Manager ARN for API keys."
  value       = module.openclaw.secret_arn
}
