variable "service_name" {
  type        = string
  description = "Service name used for resource naming, tags, and Cognito pool."
  default     = "openclaw"
}

variable "environment" {
  type        = string
  description = "Environment name (e.g. production, development)."

  validation {
    condition     = can(regex("^[a-z0-9_]+$", var.environment))
    error_message = "environment must contain only lowercase letters, numbers, and underscores. Got: ${var.environment}"
  }
}

variable "dns_a_records" {
  type        = list(string)
  description = <<-EOT
    A record names in the zone that resolve to the ALB.
    Use ["openclaw"] for openclaw.infrahouse.com,
    [""] for zone apex, ["", "www"] for both.
  EOT
  default     = ["openclaw"]
}

variable "zone_id" {
  type        = string
  description = "Route53 hosted zone ID for DNS validation and the A record."
}

variable "alb_subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for the ALB (public subnets in at least two AZs)."

  validation {
    condition     = length(var.alb_subnet_ids) >= 2
    error_message = "At least 2 subnets required for the ALB. Provided: ${length(var.alb_subnet_ids)}"
  }
}

variable "backend_subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for the EC2 instances (can be private subnets with NAT)."

  validation {
    condition     = length(var.backend_subnet_ids) >= 1
    error_message = "At least 1 backend subnet required. Provided: ${length(var.backend_subnet_ids)}"
  }
}

variable "instance_type" {
  type        = string
  description = <<-EOT
    EC2 instance type.
    t3.medium (4 GB) minimum for OpenClaw + cloud LLMs only.
    t3.large (8 GB) recommended for OpenClaw + Ollama with small local models.
    t3.xlarge (16 GB) for larger local models.
  EOT
  default     = "t3.large"
}

variable "key_name" {
  type        = string
  description = "EC2 key pair name for SSH access. If null, a key pair is auto-generated."
  default     = null
}

variable "allowed_cidrs" {
  type        = list(string)
  description = <<-EOT
    CIDRs allowed to reach the ALB on ports 80/443.
    Defaults to public access; Cognito authentication protects the application.
  EOT
  default     = ["0.0.0.0/0"]
}

variable "extra_bedrock_models" {
  type = list(object({
    id            = string
    name          = optional(string)
    reasoning     = optional(bool, false)
    input         = optional(list(string), ["text"])
    contextWindow = optional(number, 128000)
    maxTokens     = optional(number, 8192)
  }))
  description = <<-EOT
    Additional Bedrock models to register in OpenClaw.
    Use inference profile IDs (with us./eu./ap. prefix).

    The module includes common Claude and Nova models by default.
    Use this variable to add models not in the default list.

    Example:
      extra_bedrock_models = [
        {
          id   = "us.meta.llama3-1-70b-instruct-v1:0"
          name = "Llama 3.1 70B"
        },
      ]
  EOT
  default     = []
}

variable "root_volume_size" {
  type        = number
  description = "Root EBS volume size in GB. 30 GB minimum recommended for Ollama models."
  default     = 30

  validation {
    condition     = var.root_volume_size >= 20
    error_message = "root_volume_size must be at least 20 GB. Got: ${var.root_volume_size}"
  }
}

variable "ollama_default_model" {
  type        = string
  description = "Default Ollama model to pull on instance bootstrap. Set to null to skip."
  default     = "qwen2.5:1.5b"
  nullable    = true
}

variable "extra_packages" {
  type        = list(string)
  description = "Additional APT packages to install on the instance (e.g. gh for GitHub skill)."
  default     = []
}

variable "alarm_emails" {
  type        = list(string)
  description = "Email addresses for CloudWatch alarm notifications (ALB health, latency, 5xx)."
}

variable "extra_instance_permissions" {
  type        = string
  description = "Additional IAM policy document JSON to attach to the instance role (merged with module-managed permissions)."
  default     = null
}

variable "enable_deletion_protection" {
  type        = bool
  description = "Enable deletion protection on ALB and Cognito user pool. Disable for testing."
  default     = true
}

variable "alb_access_log_force_destroy" {
  type        = bool
  description = "Destroy ALB access log S3 bucket even if non-empty. Enable for testing."
  default     = false
}

variable "cognito_users" {
  type = list(
    object({
      email     = string
      full_name = string
    })
  )
  description = "List of Cognito users to create with email and full name."
}

