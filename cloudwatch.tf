# ------------------------------------------------------------------------------
# CloudWatch log group for OpenClaw application logs
#
# 365-day retention per ISO27001/SOC2 compliance requirements.
# The CloudWatch agent on the instance forwards journald logs here.
# ------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/ec2/${var.service_name}/${var.environment}"
  retention_in_days = 365

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
