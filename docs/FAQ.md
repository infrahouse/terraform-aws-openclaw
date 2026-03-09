# OpenClaw FAQ

## Getting Bedrock Models Working

After deploying the module, Bedrock models require a few one-time
setup steps before they work. Here's what to expect and how to fix
each issue.

### Step 1: AWS Marketplace subscription

**Error:** `Model access is denied due to IAM user or service role
is not authorized to perform the required AWS Marketplace actions`

Bedrock models are delivered through AWS Marketplace. On first use,
AWS auto-subscribes your account, but the instance role needs
Marketplace permissions (included in this module by default).

If you see this error:

1. Open **AWS Console > Bedrock > Model catalog** as an admin user.
2. Select the model (e.g. Claude Sonnet 4.6) and open in playground.
3. AWS will create the Marketplace subscription automatically.
4. Wait 2 minutes, then retry from OpenClaw.

You'll receive a confirmation email from AWS Marketplace. This is a
one-time step per model provider.

### Step 2: Anthropic use case form

**Error:** `Model use case details have not been submitted for this
account`

Anthropic is the only Bedrock provider that requires a use case form.
Other providers (Amazon Nova, Meta, Mistral, etc.) work immediately.

1. Open **AWS Console > Bedrock > Model catalog**.
2. Select any Claude model and open in playground.
3. Fill out the use case form (company name, website, intended use).
   This is a one-time step — once per AWS account.
4. Wait up to 15 minutes for activation.
5. You'll receive a confirmation email from AWS Marketplace.

### Step 3: Inference profile prefix

**Error:** `Invocation of model ID ... with on-demand throughput
isn't supported`

Bedrock models require **cross-region inference profiles**. The
module pre-configures common models with the correct `us.` prefix.
If you use a model from the `/models` list that doesn't have the
prefix, add it manually:

```
# Wrong (auto-discovered without prefix)
/model amazon-bedrock/anthropic.claude-sonnet-4-6

# Correct (with inference profile prefix)
/model amazon-bedrock/us.anthropic.claude-sonnet-4-6
```

Prefixes by region: `us.` (Americas), `eu.` (Europe), `ap.`
(Asia-Pacific).

To add more models with the correct prefix, use the
`extra_bedrock_models` variable:

```hcl
module "openclaw" {
  # ...
  extra_bedrock_models = [
    {
      id   = "us.meta.llama3-1-70b-instruct-v1:0"
      name = "Llama 3.1 70B"
    },
  ]
}
```

### Other Bedrock errors

**"The provided model identifier is invalid"** — The model ID
doesn't exist. List available models:

```bash
aws bedrock list-foundation-models \
  --query "modelSummaries[].modelId" --output text \
  | tr '\t' '\n' | sort
```

**"is not authorized to perform: bedrock:InvokeModel"** — Bedrock
permissions are always included. Run `terraform apply` to ensure the
latest IAM policy is deployed.

## Ollama (Local Models)

### Ollama model is very slow / CPU at 100%

Ollama runs models on CPU (no GPU on standard EC2 instances). Small
models (1-3B parameters) are usable for short responses on a t3.large.
Larger models need more RAM and CPU:

| Model size | RAM needed | Recommended instance |
|-----------|-----------|---------------------|
| 1-3B | 2-4 GB | t3.large (8 GB) |
| 7-8B | 5-8 GB | t3.xlarge (16 GB) |
| 13-14B | 10-16 GB | r6i.xlarge (32 GB) |
| 30-34B | 20-36 GB | r6i.2xlarge (64 GB) |
| 70B | 40-48 GB | r6i.4xlarge (128 GB) |

For production use, **Bedrock is recommended** over local Ollama models.
Ollama is best for experimentation with small models.

### Ollama model not responding / instance swapping

The model is too large for the instance RAM. Check with:

```bash
free -h          # Check available memory
swapon --show    # Check swap usage
ollama list      # Check loaded models
```

Either switch to a smaller model or upgrade the instance type.

## Authentication

### "Unauthorized: gateway token missing"

The gateway is configured for `trusted-proxy` auth mode, which means
it expects traffic from the ALB with Cognito authentication headers.
Direct access to the instance bypasses this. Always access OpenClaw
through the ALB URL (e.g. `https://openclaw.example.com`).

### WebSocket errors / "Origin not allowed"

The `controlUi.allowedOrigins` in the OpenClaw config must match
the URL you're accessing. This is automatically configured from
the DNS settings. If you changed DNS records, run `make plan apply`
to update the config.

## Configuration

### How to change OpenClaw settings?

**Infrastructure settings** (auth, networking, providers) are managed
by Terraform in `locals.tf`. Run `make plan apply` after changes.

**Operational settings** (Telegram, channels, agent behavior) are
configured through the OpenClaw web UI or CLI. These persist on EFS
across instance redeployments.

Terraform uses deep-merge: infrastructure settings always win, but
operational settings you configure in the UI are preserved.

### How to add API keys (Anthropic, OpenAI)?

Create a JSON file with your keys (`{"ANTHROPIC_API_KEY": "sk-...", "OPENAI_API_KEY": "sk-..."}`):

```bash
ih-secrets set $(terraform output -raw secret_name) api-keys.json
terraform apply
```
