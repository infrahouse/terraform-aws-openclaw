# ------------------------------------------------------------------------------
# Combined IAM policy for the instance profile
# Grants: Bedrock invoke, Secrets Manager read, CloudWatch logs
#
# SSM Session Manager is handled by website-pod's instance profile.
# ------------------------------------------------------------------------------

data "aws_iam_policy_document" "combined_permissions" {
  source_policy_documents = compact([
    data.aws_iam_policy_document.instance_permissions.json,
    data.aws_iam_policy_document.cloudwatch_logs.json,
    var.extra_instance_permissions,
  ])
}

data "aws_iam_policy_document" "instance_permissions" {
  # Bedrock model invocation
  # Grant access to all foundation models and inference profiles.
  # Newer models (e.g. claude-sonnet-4-6) require inference profiles
  # (us.anthropic.claude-sonnet-4-6) rather than direct foundation model calls.
  statement {
    sid    = "BedrockInvoke"
    effect = "Allow"
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream",
    ]
    resources = [
      "arn:aws:bedrock:*::foundation-model/*",
      "arn:aws:bedrock:${data.aws_region.this.name}:${data.aws_caller_identity.this.account_id}:inference-profile/*",
    ]
  }

  statement {
    sid    = "BedrockListAndMarketplace"
    effect = "Allow"
    actions = [
      "bedrock:ListFoundationModels",
      "bedrock:GetFoundationModel",
      "bedrock:ListInferenceProfiles",
      "bedrock:GetInferenceProfile",
      # Marketplace permissions for auto-subscribing to models
      # on first invocation (required by Bedrock).
      "aws-marketplace:ViewSubscriptions",
      "aws-marketplace:Subscribe",
    ]
    resources = ["*"]
  }

  # Secrets Manager - read API keys
  statement {
    sid    = "ReadApiKeys"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
    ]
    resources = [
      module.api_keys.secret_arn,
    ]
  }

  # Lifecycle hook completion - ih-aws autoscaling complete needs these
  statement {
    sid    = "CompleteLifecycleAction"
    effect = "Allow"
    actions = [
      "ec2:DescribeInstances",
      "autoscaling:CompleteLifecycleAction",
    ]
    resources = ["*"]
  }
}

# --- Secrets Manager secret for LLM API keys ---

module "api_keys" {
  source             = "registry.infrahouse.com/infrahouse/secret/aws"
  version            = "1.1.1"
  secret_description = "LLM provider API keys for OpenClaw (Anthropic, OpenAI, etc.)."
  secret_name_prefix = "${var.service_name}/api-keys-"
  environment        = var.environment
  readers = [
    data.aws_iam_role.instance.arn
  ]
  writers = var.api_keys_writers
}

