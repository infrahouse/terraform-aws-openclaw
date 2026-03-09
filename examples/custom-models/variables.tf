variable "environment" {
  type        = string
  description = "Environment name."
  default     = "development"
}

variable "zone_id" {
  type        = string
  description = "Route53 hosted zone ID."
}

variable "alb_subnet_ids" {
  type        = list(string)
  description = "Public subnet IDs for the ALB."
}

variable "backend_subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs for EC2."
}

variable "alarm_emails" {
  type        = list(string)
  description = "Email addresses for CloudWatch alarms."
}