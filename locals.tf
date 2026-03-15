locals {
  module_version = "0.3.3"

  zone_name = trimsuffix(data.aws_route53_zone.this.name, ".")
  # Build the FQDN from the first A record entry and the zone name.
  # "" → "infrahouse.com", "openclaw" → "openclaw.infrahouse.com"
  fqdn = (
    var.dns_a_records[0] == ""
    ? local.zone_name
    : "${var.dns_a_records[0]}.${local.zone_name}"
  )

  default_module_tags = {
    environment       = var.environment
    service           = var.service_name
    created_by_module = "infrahouse/openclaw/aws"
  }

  # Default Bedrock models with us. inference profile prefix.
  # OpenClaw bug #5290: auto-discovery lists foundation model IDs
  # that don't work for on-demand invocation.
  #
  # Only Amazon Nova models are included by default — they work without
  # extra setup. Claude models require Anthropic's Bedrock use case form
  # and can cause reasoning-related errors; add them via extra_bedrock_models
  # after completing the form.
  default_bedrock_models = [
    {
      id            = "us.amazon.nova-2-lite-v1:0"
      name          = "Amazon Nova 2 Lite"
      reasoning     = true
      input         = ["text", "image"]
      contextWindow = 1000000
      maxTokens     = 5120
    },
    {
      id            = "us.amazon.nova-pro-v1:0"
      name          = "Amazon Nova Pro"
      input         = ["text", "image"]
      contextWindow = 300000
      maxTokens     = 5120
    },
    {
      id            = "us.amazon.nova-lite-v1:0"
      name          = "Amazon Nova Lite"
      input         = ["text", "image"]
      contextWindow = 300000
      maxTokens     = 5120
    },
    {
      id            = "us.amazon.nova-micro-v1:0"
      name          = "Amazon Nova Micro"
      input         = ["text"]
      contextWindow = 128000
      maxTokens     = 5120
    },
  ]

  # Default to Nova 2 Lite — supports reasoning, no use case registration needed.
  # Claude models require filling out the Anthropic Bedrock use case form first.
  primary_model = "amazon-bedrock/us.amazon.nova-2-lite-v1:0"

  # Model providers configured in openclaw.json
  model_providers = {
    "amazon-bedrock" = {
      baseUrl = "https://bedrock-runtime.${data.aws_region.this.name}.amazonaws.com"
      api     = "bedrock-converse-stream"
      auth    = "aws-sdk"
      # Explicit models with us. inference profile prefix.
      # OpenClaw bug #5290: auto-discovery only lists foundation model
      # IDs which don't work for on-demand invocation.
      models = concat(local.default_bedrock_models, var.extra_bedrock_models)
    }
    anthropic = {
      baseUrl = "https://api.anthropic.com"
      models  = []
    }
    openai = {
      baseUrl = "https://api.openai.com/v1"
      models  = []
    }
    ollama = {
      baseUrl = "http://127.0.0.1:11434/v1"
      apiKey  = "ollama-local"
      api     = "openai-completions"
      models  = []
    }
  }

  openclaw_config = {
    gateway = {
      mode = "local"
      port = 5173
      bind = "lan"
      auth = {
        mode = "trusted-proxy"
        trustedProxy = {
          userHeader = "x-amzn-oidc-identity"
        }
      }
      trustedProxies = [for s in data.aws_subnet.alb : s.cidr_block]
      controlUi = {
        allowedOrigins = ["https://${local.fqdn}"]
      }
    }
    agents = {
      defaults = {
        maxConcurrent = 4
        compaction    = { mode = "safeguard" }
        model         = local.primary_model
      }
    }
    models = {
      providers = local.model_providers
    }
  }
}
