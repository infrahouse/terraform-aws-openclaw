# ------------------------------------------------------------------------------
# CloudWatch log group for OpenClaw application logs
#
# 365-day retention per ISO27001/SOC2 compliance requirements.
# The CloudWatch agent on the instance forwards journald logs here.
# Encrypted with a customer-managed KMS key.
# ------------------------------------------------------------------------------

resource "aws_kms_key" "cloudwatch" {
  description         = "KMS key for ${var.service_name} CloudWatch log group"
  enable_key_rotation = true

  policy = data.aws_iam_policy_document.cloudwatch_kms.json

  tags = local.default_module_tags
}

resource "aws_kms_alias" "cloudwatch" {
  name          = "alias/${var.service_name}-cloudwatch-logs-${random_string.cloudwatch_kms.result}"
  target_key_id = aws_kms_key.cloudwatch.key_id
}

resource "random_string" "cloudwatch_kms" {
  length  = 6
  special = false
  upper   = false
}

data "aws_iam_policy_document" "cloudwatch_kms" {
  # Allow the account root full control over the key
  statement {
    sid    = "EnableRootPermissions"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.this.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  # Allow CloudWatch Logs service to use the key
  statement {
    sid    = "AllowCloudWatchLogs"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["logs.${data.aws_region.this.name}.amazonaws.com"]
    }
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = ["*"]
    condition {
      test     = "ArnEquals"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:${data.aws_region.this.name}:${data.aws_caller_identity.this.account_id}:log-group:/aws/ec2/${var.service_name}/${var.environment}"]
    }
  }
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/ec2/${var.service_name}/${var.environment}"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.cloudwatch.arn

  tags = local.default_module_tags
}

# IAM permissions for CloudWatch Logs
data "aws_iam_policy_document" "cloudwatch_logs" {
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = [
      aws_cloudwatch_log_group.this.arn,
      "${aws_cloudwatch_log_group.this.arn}:*",
    ]
  }
}
