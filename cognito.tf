# ------------------------------------------------------------------------------
# Cognito User Pool + App Client for ALB authentication
# ------------------------------------------------------------------------------

resource "aws_cognito_user_pool" "this" {
  name                = var.service_name
  deletion_protection = var.enable_deletion_protection ? "ACTIVE" : "INACTIVE"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  user_pool_add_ons {
    advanced_security_mode = "ENFORCED"
  }

  mfa_configuration = "OPTIONAL"
  software_token_mfa_configuration {
    enabled = true
  }

  password_policy {
    minimum_length    = 12
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = true
  }

  admin_create_user_config {
    allow_admin_create_user_only = true

    invite_message_template {
      email_subject = "Your ${var.service_name} account on https://${local.fqdn}"
      email_message = <<-EOT
        <p>Hello,</p>
        <p>An account has been created for you on
        <a href="https://${local.fqdn}">https://${local.fqdn}</a>.</p>
        <p>Your username is <strong>{username}</strong></p>
        <p>Your temporary password is:</p>
        <p><code style="font-size:1.2em;padding:4px 8px;background:#f0f0f0;border:1px solid #ccc;border-radius:4px">{####}</code></p>
        <p>You will be asked to change your password on first login.</p>
      EOT
      sms_message   = "Your ${var.service_name} username is {username} and temporary password is {####}"
    }
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  schema {
    attribute_data_type      = "String"
    developer_only_attribute = false
    mutable                  = true
    name                     = "name"
    required                 = false
    string_attribute_constraints {
      max_length = "2048"
      min_length = "0"
    }
  }

  tags = local.default_module_tags
}

resource "aws_cognito_user_pool_domain" "this" {
  domain       = "${var.service_name}-${data.aws_caller_identity.this.account_id}"
  user_pool_id = aws_cognito_user_pool.this.id
}

resource "aws_cognito_user_pool_client" "this" {
  name         = "${var.service_name}-alb"
  user_pool_id = aws_cognito_user_pool.this.id

  generate_secret = true

  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  allowed_oauth_flows_user_pool_client = true
  supported_identity_providers         = ["COGNITO"]

  callback_urls = [
    "https://${local.fqdn}/oauth2/idpresponse"
  ]

  logout_urls = [
    "https://${local.fqdn}/"
  ]
}

# ------------------------------------------------------------------------------
# Cognito users - auto-generated temporary passwords
#
# Temporary passwords are stored in Terraform state. This is acceptable because
# state is treated as secret (encrypted S3 bucket with restricted access) and
# users must change the password on first login (allow_admin_create_user_only).
# ------------------------------------------------------------------------------

resource "random_password" "users" {
  for_each = { for user in var.cognito_users : user.email => user }
  length   = 24

  min_lower   = 1
  min_numeric = 1
  min_special = 1
  min_upper   = 1
}

resource "aws_cognito_user" "users" {
  for_each = { for user in var.cognito_users : user.email => user }

  user_pool_id = aws_cognito_user_pool.this.id
  username     = each.value.email

  attributes = {
    email          = each.value.email
    email_verified = "true"
    name           = each.value.full_name
  }
  temporary_password = random_password.users[each.key].result
}

# ------------------------------------------------------------------------------
# ALB listener rule with Cognito authentication
#
# Fires at priority 1, before website-pod's default rule (priority 99).
# ------------------------------------------------------------------------------

resource "aws_lb_listener_rule" "cognito_auth" {
  listener_arn = module.openclaw_pod.ssl_listener_arn
  priority     = 1

  action {
    type  = "authenticate-cognito"
    order = 1

    authenticate_cognito {
      user_pool_arn       = aws_cognito_user_pool.this.arn
      user_pool_client_id = aws_cognito_user_pool_client.this.id
      user_pool_domain    = aws_cognito_user_pool_domain.this.domain

      on_unauthenticated_request = "authenticate"
      scope                      = "openid email profile"
      session_timeout            = 86400
    }
  }

  action {
    type             = "forward"
    target_group_arn = module.openclaw_pod.target_group_arn
    order            = 2
  }

  condition {
    host_header {
      values = [local.fqdn]
    }
  }

  tags = local.default_module_tags
}
