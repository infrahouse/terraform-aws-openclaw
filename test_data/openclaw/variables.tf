variable "region" {
  description = "AWS region"
  type        = string
}

variable "role_arn" {
  description = "IAM role ARN to assume"
  type        = string
  default     = null
}

variable "subnet_public_ids" {
  description = "List of public subnet IDs for the ALB"
  type        = list(string)
}

variable "subnet_private_ids" {
  description = "List of private subnet IDs for the backend"
  type        = list(string)
}

variable "zone_id" {
  description = "Route53 hosted zone ID"
  type        = string
}

variable "alarm_emails" {
  description = "Email addresses for CloudWatch alarm notifications"
  type        = list(string)
  default     = ["aleks+terraform-aws-openclaw@infrahouse.com"]
}
