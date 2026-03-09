# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Terraform module (`terraform-aws-openclaw`) that deploys [OpenClaw](https://github.com/openclaw) AI agent gateway on AWS. Uses EC2 behind an ALB with Cognito authentication, supporting multiple LLM providers (Bedrock, Anthropic API, OpenAI API, Ollama).

## Common Commands

```bash
# Format Terraform files (pre-commit hook checks this)
terraform fmt -recursive

# Lint (Terraform formatting + YAML linting)
make lint

# Run all tests (pytest-based, requires AWS credentials)
make test                # or: pytest -xvvs tests/

# Run tests keeping resources for debugging
make test-keep

# Run tests and destroy resources
make test-clean

# Bootstrap dev environment
make bootstrap           # installs pip deps from requirements.txt

# Install git hooks (auto-runs on `make help`)
make install-hooks

# Generate terraform-docs (updates README.md between TF_DOCS markers)
terraform-docs .
```

## Architecture

The module composes several InfraHouse registry modules and AWS resources:

**Core deployment (`main.tf`):**
- `infrahouse/website-pod/aws` — ALB + ASG + ACM + DNS + security groups. Single-instance ASG (`asg_min=1, max=1`) since OpenClaw is stateful. ALB health checks on port 5173.
- `infrahouse/cloud-init/aws` — Generates cloud-init userdata that installs packages, mounts EFS, and runs the setup script.

**Authentication (`cognito.tf`):**
- Cognito User Pool with admin-only user creation, optional MFA, and advanced security.
- ALB listener rule at priority 1 injects Cognito OIDC auth before forwarding to the target group.
- OpenClaw trusts the `x-amzn-oidc-identity` header from the ALB (`trusted-proxy` auth mode).

**Persistence (`efs.tf`):**
- EFS filesystem mounted at `/home/openclaw/.openclaw` survives instance replacement.
- Operational settings (configured via OpenClaw UI) persist on EFS; Terraform deep-merges infrastructure settings over them on each deploy.

**Secrets (`iam.tf`):**
- `infrahouse/secret/aws` module creates a KMS-encrypted Secrets Manager secret for LLM API keys.
- Instance role gets `secretsmanager:GetSecretValue` on the secret ARN, plus optional Bedrock invoke permissions.

**Bootstrap (`setup-openclaw.py.tftpl`):**
- Python script rendered by Terraform's `templatefile()`. Runs as cloud-init `post_runcmd`.
- Fetches API keys via `ih-secrets`, installs OpenClaw via npm, deep-merges config, installs Ollama from binary tarball, configures CloudWatch agent, starts systemd services.

**Configuration flow:**
- `locals.tf` builds `openclaw_config` (gateway auth, model providers, allowed origins) from variables and data sources.
- Config is JSON-encoded into the setup script template, which writes it to `/home/openclaw/.openclaw/openclaw.json`.
- Bedrock models use inference profile IDs with `us.` prefix (not foundation model IDs) — see `locals.tf` comment about OpenClaw bug #5290.

## Provider Configuration

Requires two AWS provider configurations: `aws` (default) and `aws.dns` (for Route53 in potentially different account). Terraform >= 1.5, AWS provider ~> 6.0.

## Pre-commit Hook

The pre-commit hook runs `terraform fmt -check -recursive` and updates README.md via `terraform-docs`. Both hooks are managed externally in the `infrahouse8/github-control` repo — do not edit files in `hooks/` directly.

## CI Workflows

- **terraform-review.yml** — Claude Code reviews PR diffs as a Terraform module reviewer, posts findings as PR comments.
- **checkov.yml** — Runs Checkov security scanner on PRs to main.
- GitHub workflows are managed by Terraform in `infrahouse8/github-control` — do not edit `.github/workflows/` directly.

## Local Review

Use `/review-local` skill to run Terraform module review locally (similar to GitHub PR review).