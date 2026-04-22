# terraform-aws-openclaw

Terraform module for deploying [OpenClaw](https://github.com/openclaw)
AI agent gateway on AWS with ALB, Cognito authentication, EFS
persistence, and multi-provider LLM support (Bedrock, Anthropic,
OpenAI, Ollama).

## Architecture

![Architecture](assets/architecture.svg)

## Features

- **ALB with Cognito authentication** — HTTPS with ACM certificate,
  Cognito OIDC auth on the listener
- **Multi-provider LLM support** — AWS Bedrock (IAM-based), Anthropic
  API, OpenAI API, and Ollama for local inference
- **EFS persistence** — config and agent data survive instance
  replacement via deep-merge strategy
- **Secrets Manager** — KMS-encrypted storage for API keys
- **CloudWatch logging** — 365-day retention for ISO27001/SOC2
  compliance
- **Cognito user management** — pre-created users with email
  invitations, optional MFA, advanced security
- **Systemd hardening** — ProtectSystem, ProtectHome,
  NoNewPrivileges

## Quick Start

```hcl
module "openclaw" {
  source  = "registry.infrahouse.com/infrahouse/openclaw/aws"
  version = "0.4.0"
  providers = {
    aws     = aws
    aws.dns = aws
  }

  environment        = "production"
  zone_id            = aws_route53_zone.example.zone_id
  alb_subnet_ids     = module.network.subnet_public_ids
  backend_subnet_ids = module.network.subnet_private_ids
  alarm_emails       = ["ops@example.com"]

  cognito_users = [
    {
      email     = "admin@example.com"
      full_name = "Admin User"
    },
  ]
}
```

The module creates a Secrets Manager secret for passing environment
variables (API keys, tokens, etc.) to OpenClaw. Set `api_keys_writers`
to grant write access, then populate it with any key/value pairs:

```json
{
  "ANTHROPIC_API_KEY": "sk-...",
  "OPENAI_API_KEY": "sk-...",
  "MY_CUSTOM_SECRET": "some-value"
}
```

```bash
ih-secrets set $(terraform output -raw secret_name) secrets.json
terraform apply
```

## Next Steps

- [Getting Started](getting-started.md) — prerequisites and first
  deployment
- [Configuration](configuration.md) — all variables explained
- [Architecture](architecture.md) — how it works under the hood
- [Security](security-considerations.md) — auth, supply chain,
  systemd hardening, and network isolation
- [FAQ](FAQ.md) — common issues and troubleshooting
