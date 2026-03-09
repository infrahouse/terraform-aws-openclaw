module "openclaw" {
  source  = "registry.infrahouse.com/infrahouse/openclaw/aws"
  version = "0.1.0"
  providers = {
    aws     = aws
    aws.dns = aws
  }

  environment        = var.environment
  zone_id            = var.zone_id
  alb_subnet_ids     = var.alb_subnet_ids
  backend_subnet_ids = var.backend_subnet_ids
  alarm_emails       = var.alarm_emails

  # Larger instance for a bigger local model
  instance_type        = "r6i.xlarge"
  ollama_default_model = "qwen2.5:14b"
  root_volume_size     = 50

  # Add Bedrock models not in the default list
  extra_bedrock_models = [
    {
      id   = "us.meta.llama3-1-70b-instruct-v1:0"
      name = "Llama 3.1 70B"
    },
    {
      id            = "us.mistral.mistral-large-2407-v1:0"
      name          = "Mistral Large"
      contextWindow = 128000
      maxTokens     = 8192
    },
  ]

  cognito_users = [
    {
      email     = "admin@example.com"
      full_name = "Admin User"
    },
    {
      email     = "developer@example.com"
      full_name = "Dev User"
    },
  ]
}