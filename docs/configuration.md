# Configuration

## Required Variables

| Variable | Description |
|----------|-------------|
| `environment` | Environment name (lowercase, numbers, underscores only). |
| `zone_id` | Route53 hosted zone ID for DNS and certificate validation. |
| `alb_subnet_ids` | Public subnet IDs for the ALB (minimum 2 AZs). |
| `backend_subnet_ids` | Private subnet IDs for the EC2 instance (minimum 1). |
| `alarm_emails` | Email addresses for CloudWatch alarm notifications. |
| `cognito_users` | Users to create with `email` and `full_name`. |

## Optional Variables

### Networking & DNS

| Variable | Default | Description |
|----------|---------|-------------|
| `service_name` | `"openclaw"` | Used for resource naming, tags, and Cognito pool. |
| `dns_a_records` | `["openclaw"]` | A record names in the zone. `[""]` for zone apex. |
| `allowed_cidrs` | `["0.0.0.0/0"]` | CIDRs allowed to reach the ALB. Cognito protects the app. |

### Compute

| Variable | Default | Description |
|----------|---------|-------------|
| `instance_type` | `"t3.large"` | EC2 instance type. Size based on Ollama model needs. |
| `key_name` | `null` | EC2 key pair name. Auto-generates ED25519 key if null. |
| `root_volume_size` | `30` | Root EBS volume size in GB (minimum 20). |
| `extra_packages` | `[]` | Additional APT packages to install. |

### LLM Providers

| Variable | Default | Description |
|----------|---------|-------------|
| `extra_bedrock_models` | `[]` | Additional Bedrock models with `us.` inference profile prefix. |
| `ollama_default_model` | `"qwen2.5:1.5b"` | Ollama model to pre-pull. Set to `null` to skip. |

## LLM Provider Configuration

### AWS Bedrock

Always enabled. Uses IAM role credentials — no API keys needed.
The module pre-configures these models with cross-region inference
profile IDs:

- Amazon Nova 2 Lite (default primary model, supports reasoning)
- Amazon Nova Pro / Lite / Micro

Claude models require completing the
[Anthropic Bedrock use case form](FAQ.md#step-2-anthropic-use-case-form)
first. Add them via `extra_bedrock_models` after activation.

Add more models via `extra_bedrock_models`:

```hcl
extra_bedrock_models = [
  {
    id   = "us.meta.llama3-1-70b-instruct-v1:0"
    name = "Llama 3.1 70B"
  },
]
```

### Anthropic API / OpenAI API

Store API keys in the Secrets Manager secret created by the module.
Create a JSON file (e.g. `api-keys.json`):

```json
{"ANTHROPIC_API_KEY": "sk-...", "OPENAI_API_KEY": "sk-..."}
```

```bash
ih-secrets set $(terraform output -raw secret_name) api-keys.json
terraform apply
```

### Ollama

Always installed. The `ollama_default_model` is pulled during
bootstrap. Additional models can be pulled via SSH or the OpenClaw UI.

## Config Deep-Merge

The module uses a deep-merge strategy for OpenClaw configuration:

- **Terraform-managed** (always wins): auth mode, trusted proxies,
  allowed origins, model providers
- **User-managed** (persists on EFS): Telegram config, channels,
  agent behavior tweaks

This means you can change settings in the OpenClaw UI and they
survive instance replacement, while Terraform keeps infrastructure
settings consistent.

## Instance Sizing

See the [README](https://github.com/infrahouse/terraform-aws-openclaw#instance-sizing-for-ollama-models)
for the Ollama model sizing table.