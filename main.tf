# ------------------------------------------------------------------------------
# Auto-generated SSH key pair (when var.key_name is null)
# ------------------------------------------------------------------------------

resource "tls_private_key" "this" {
  count     = var.key_name == null ? 1 : 0
  algorithm = "ED25519"
}

resource "aws_key_pair" "this" {
  count      = var.key_name == null ? 1 : 0
  key_name   = var.service_name
  public_key = tls_private_key.this[0].public_key_openssh
}

# ------------------------------------------------------------------------------
# Website Pod - ALB, ASG, ACM, DNS, security groups
# ------------------------------------------------------------------------------

module "openclaw_pod" {
  source  = "registry.infrahouse.com/infrahouse/website-pod/aws"
  version = "5.17.0"
  providers = {
    aws     = aws
    aws.dns = aws.dns
  }

  ami              = data.aws_ami.infrahouse_pro_noble.id
  environment      = var.environment
  service_name     = var.service_name
  zone_id          = var.zone_id
  dns_a_records    = var.dns_a_records
  subnets          = var.alb_subnet_ids
  backend_subnets  = var.backend_subnet_ids
  key_pair_name    = var.key_name != null ? var.key_name : aws_key_pair.this[0].key_name
  instance_type    = var.instance_type
  root_volume_size = var.root_volume_size
  userdata         = module.openclaw_userdata.userdata

  # Single instance for stateful OpenClaw; scale out is not meaningful
  asg_min_size = 1
  asg_max_size = 1

  # ELB health checks: ASG replaces instances that fail ALB health checks.
  # Lifecycle hook ensures instance is fully set up before reaching InService,
  # so a short grace period is sufficient for ALB target registration.
  health_check_type         = "ELB"
  health_check_grace_period = 60

  # ALB settings
  alb_name_prefix                       = "${substr(var.service_name, 0, 5)}-"
  alb_access_log_enabled                = true
  alb_ingress_cidr_blocks               = var.allowed_cidrs
  alb_healthcheck_path                  = "/"
  alb_healthcheck_port                  = 5173
  alb_healthcheck_response_code_matcher = "200-399"
  alb_healthcheck_interval              = 30
  alb_healthcheck_timeout               = 5
  alb_healthcheck_healthy_threshold     = 2
  # 5 × 30s = 150s of sustained failure before the target is unhealthy.
  # OpenClaw restarts itself on config changes (UI or Terraform push) and
  # port 5173 is gone for ~45s; a lower threshold turns that into instance
  # replacement, which punishes users for making expected config changes.
  alb_healthcheck_unhealthy_threshold = 5
  enable_deletion_protection          = var.enable_deletion_protection
  alb_access_log_force_destroy        = var.alb_access_log_force_destroy
  stickiness_enabled                  = true
  target_group_port                   = 5173

  # Lifecycle hooks: instance stays in Pending:Wait until setup-openclaw.py completes
  asg_lifecycle_hook_initial           = "${var.service_name}-launching"
  asg_lifecycle_hook_launching         = "${var.service_name}-launching"
  asg_lifecycle_hook_heartbeat_timeout = 1800

  # CloudWatch alarms
  alarm_emails = var.alarm_emails

  # Instance profile permissions for Bedrock + Secrets Manager + CloudWatch
  instance_profile_permissions = data.aws_iam_policy_document.combined_permissions.json

  tags = local.default_module_tags
}

# ------------------------------------------------------------------------------
# Cloud-init userdata
# ------------------------------------------------------------------------------

module "openclaw_userdata" {
  source  = "registry.infrahouse.com/infrahouse/cloud-init/aws"
  version = "2.3.1"

  environment   = var.environment
  role          = "base"
  gzip_userdata = true

  # Auto-signal the launching lifecycle hook: CONTINUE at end of a successful
  # bootstrap, ABANDON via ERR trap on any failure. setup-openclaw.py must
  # therefore block until OpenClaw is actually serving traffic on :5173.
  lifecycle_hook_name = "${var.service_name}-launching"

  extra_files = [
    {
      content     = file("${path.module}/templates/openclaw.service")
      path        = "/etc/systemd/system/openclaw.service"
      permissions = "0644"
    },
    {
      content = templatefile("${path.module}/templates/setup-openclaw.py.tftpl", {
        secret_name          = module.api_keys.secret_name
        aws_region           = data.aws_region.this.name
        openclaw_config_json = jsonencode(local.openclaw_config)
        cloudwatch_log_group = aws_cloudwatch_log_group.this.name
        ollama_default_model = var.ollama_default_model
        ollama_version       = var.ollama_version == null ? "" : var.ollama_version
      })
      path        = "/opt/openclaw/setup-openclaw.py"
      permissions = "0755"
    },
    {
      content = templatefile("${path.module}/templates/mount-efs.py.tftpl", {
        efs_dns_name = aws_efs_file_system.this.dns_name
        mount_point  = "/home/openclaw/.openclaw"
      })
      path        = "/opt/openclaw/mount-efs.py"
      permissions = "0755"
    },
  ]

  extra_repos = {
    nodesource = {
      source = "deb [signed-by=$KEY_FILE] https://deb.nodesource.com/node_22.x nodistro main"
      keyid  = "6F71F525282841EEDAF851B42F59B5F99B1BE0B4"
    }
  }

  packages = concat(
    [
      "curl",
      "infrahouse-toolkit",
      "nfs-common",
      "unzip",
      "git",
      "build-essential",
      "nodejs",
      "zstd",
    ],
    var.extra_packages,
  )

  # Mount EFS at /home/openclaw/.openclaw for persistent agent data.
  # The mounts directive writes /etc/fstab but mount -a may fail if DNS
  # isn't ready yet. We retry in pre_runcmd to handle the race.
  mounts = [
    [
      "${aws_efs_file_system.this.dns_name}:/",
      "/home/openclaw/.openclaw",
      "nfs4",
      "nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport,_netdev",
      "0",
      "0",
    ]
  ]

  pre_runcmd = [
    "useradd --system --create-home --shell /bin/bash openclaw || true",
    "mkdir -p /home/openclaw/.openclaw",
    "/opt/openclaw/mount-efs.py",
  ]

  post_runcmd = [
    # Restore sudo for SSM Session Manager (Puppet purges cloud-init sudoers)
    "usermod -aG admin ssm-user",
    "/opt/openclaw/setup-openclaw.py",
  ]
}
