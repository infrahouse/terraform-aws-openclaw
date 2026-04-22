# OpenClaw Module: Security Considerations

This document captures security decisions, hardening measures, and deviations
from the default OpenClaw provisioning guide that were made to secure the
deployment behind AWS ALB + Cognito.

## Authentication Architecture

OpenClaw's default setup uses a gateway token (`auth.mode = "token"`) where
every client (browser, CLI) must present a shared secret to connect over
WebSocket. This works for single-user local installations but breaks in a
multi-user ALB-proxied deployment:

- The browser UI has no way to obtain the token automatically.
- Embedding the token in the page would defeat the purpose.

### What we changed

We use `auth.mode = "trusted-proxy"` combined with AWS Cognito authentication
at the ALB layer:

```
Browser --> ALB (Cognito auth) --> EC2 (OpenClaw, trusted-proxy)
```

- **Cognito** handles user authentication (login, MFA, password policy).
- **ALB listener rule** enforces `authenticate-cognito` action at priority 1,
  before the default website-pod rule.
- **OpenClaw** trusts the ALB as a reverse proxy via `gateway.auth.trustedProxy`
  and reads the user identity from the `x-amzn-oidc-identity` header.

Configuration in `locals.tf`:

```hcl
auth = {
  mode = "trusted-proxy"
  trustedProxy = {
    userHeader = "x-amzn-oidc-identity"
  }
}
trustedProxies = [for s in data.aws_subnet.alb : s.cidr_block]
```

### Why this is secure

1. **Security groups**: The `website-pod` module restricts backend EC2 ingress
   to only the ALB's security group (`referenced_security_group_id`). No direct
   access to port 5173 is possible from outside the ALB.
2. **Trusted proxy CIDRs**: OpenClaw only trusts proxy headers
   (`X-Forwarded-For`, `x-amzn-oidc-identity`) from the ALB subnet CIDRs.
   These CIDRs are derived automatically from `data.aws_subnet.alb`, not
   hardcoded.
3. **Header forgery protection**: Even if someone reaches the EC2 instance
   (they can't — see point 1), they would need to send requests from an ALB
   subnet IP for OpenClaw to trust the proxy headers.

### ALB headers available after Cognito authentication

| Header | Content | Signed? |
|--------|---------|---------|
| `x-amzn-oidc-data` | JWT with user claims (sub, email, name) | Yes (ES256) |
| `x-amzn-oidc-identity` | Cognito user sub (UUID) | No |
| `x-amzn-oidc-accesstoken` | OAuth2 access token | No |

We use `x-amzn-oidc-identity` because OpenClaw reads the header as a plain
string identifier. The `x-amzn-oidc-data` JWT is cryptographically verifiable
but OpenClaw does not perform JWT validation — it relies on the trusted proxy
model instead.

## Supply Chain Hardening

The default OpenClaw docs and many guides use `curl | sh` patterns for
installing dependencies. We replaced all of them:

### Node.js

**Default guide**: `curl -fsSL https://deb.nodesource.com/setup_22.x | bash -`

**Our approach**: APT repository via cloud-init `extra_repos` with GPG key
verification:

```hcl
extra_repos = {
  nodesource = {
    source = "deb [signed-by=$KEY_FILE] https://deb.nodesource.com/node_22.x nodistro main"
    keyid  = "6F71F525282841EEDAF851B42F59B5F99B1BE0B4"
  }
}
```

The GPG key is verified by fingerprint. APT will refuse packages that don't
match the signing key.

### Ollama

**Default guide**: `curl -fsSL https://ollama.com/install.sh | sh`

**Our approach**: Direct binary download from the official tarball, with manual
systemd unit creation:

```bash
curl -fsSL -o "$OLLAMA_TMP/ollama.tar.zst" \
  https://ollama.com/download/ollama-linux-amd64.tar.zst
tar --use-compress-program=unzstd -xf "$OLLAMA_TMP/ollama.tar.zst" -C "$OLLAMA_TMP"
install -m 755 "$OLLAMA_TMP/bin/ollama" /usr/local/bin/ollama
```

This avoids executing an arbitrary shell script as root. The systemd unit is
written inline in the setup script with locked-down settings (dedicated
`ollama` system user, no login shell).

### OpenClaw

**Our approach**: Local npm install under the `openclaw` user (no root):

```bash
su - openclaw -c 'mkdir -p ~/openclaw-app && cd ~/openclaw-app && npm init -y && npm install openclaw'
```

No `npm install -g` (which requires root access to `/usr/lib/node_modules`).
The systemd unit points to the local binary at
`/home/openclaw/openclaw-app/node_modules/.bin/openclaw`.

## Secrets Management

### Environment secrets

All secrets (API keys, tokens, custom credentials) are stored in a single
AWS Secrets Manager secret via the `infrahouse/secret/aws` module, which
provides KMS encryption and IAM-scoped access. The instance profile is
granted `secretsmanager:GetSecretValue` only for the specific secret ARN.
Write access is controlled separately via the `api_keys_writers` variable —
only the IAM roles listed there can populate or update the secret value.

The setup script reads the secret at boot via `ih-secrets` (from
`infrahouse-toolkit`) and writes **every key/value pair** from the JSON
to the `.openclaw-env` environment file. If the secret has not been
populated yet (returns `NoValue`), the script logs a warning and
continues — the service starts without those environment variables.

### Gateway token (removed)

Originally planned to store a gateway token in Secrets Manager. This was
removed when we switched to `trusted-proxy` auth mode. The gateway no longer
requires a shared secret — Cognito + ALB handle authentication.

## Systemd Hardening

The `openclaw.service` unit uses systemd security features:

| Directive | Effect |
|-----------|--------|
| `NoNewPrivileges=true` | Process cannot gain new privileges via setuid/setgid |
| `ProtectSystem=strict` | Entire filesystem is read-only except allowed paths |
| `ProtectHome=tmpfs` | All home directories are hidden behind an empty tmpfs |
| `BindPaths=/home/openclaw` | Only `/home/openclaw` is bind-mounted into the namespace |
| `PrivateTmp=true` | Private `/tmp` and `/var/tmp` |
| `User=openclaw` | Runs as a dedicated unprivileged user |

**Deviation from default**: The default OpenClaw install guide uses
`ProtectHome=read-only`, which exposes all home directories. We use
`ProtectHome=tmpfs` + `BindPaths` to isolate the service to only its own
home directory.

## Network Security

### ALB ingress

`var.allowed_cidrs` defaults to `["0.0.0.0/0"]` — the ALB is publicly
accessible. This is intentional: Cognito authentication is the access control
layer, not network restriction. The ALB is the only entry point.

### Backend isolation

The `website-pod` module creates a backend security group that only allows
ingress from the ALB's security group:

```hcl
resource "aws_vpc_security_group_ingress_rule" "backend_user_traffic" {
  security_group_id            = aws_security_group.backend.id
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.alb.id
}
```

No CIDR-based rules for application traffic. The EC2 instance is unreachable
except through the ALB.

### EFS encryption

The EFS filesystem (persistent agent data at `/home/openclaw/.openclaw`) is
encrypted at rest using the AWS-managed `aws/elasticfilesystem` KMS key. NFS
ingress to the EFS mount targets is restricted to the backend subnet CIDRs.

### WebSocket origin control

OpenClaw's `controlUi.allowedOrigins` is set to `["https://<fqdn>"]`, derived
from the Route53 zone and DNS A records. This prevents cross-origin WebSocket
connections from unauthorized domains.

## Cognito Hardening

| Feature | Setting | Rationale |
|---------|---------|-----------|
| `deletion_protection` | `ACTIVE` (configurable via `enable_deletion_protection`) | Prevent accidental pool deletion |
| `advanced_security_mode` | `ENFORCED` | Detect compromised credentials |
| `mfa_configuration` | `OPTIONAL` | Users can enable TOTP MFA |
| `allow_admin_create_user_only` | `true` | No self-registration |
| `password_policy.minimum_length` | `12` | Strong passwords required |
| `temporary_password` length | `24` | Margin above minimum; users must change on first login |

Temporary passwords are stored in Terraform state. This is acceptable because:
- State is stored in an encrypted S3 bucket with restricted access.
- Users must change the password on first login.
- `allow_admin_create_user_only` prevents registration bypass.

## Logging and Auditability

- **CloudWatch Logs**: journald entries for `openclaw.service` and
  `ollama.service` are forwarded to a CloudWatch log group with **365-day
  retention** (ISO 27001 / SOC 2 compliance).
- **Setup script logging**: Every step logs with `[setup-openclaw]` prefix and
  timestamp for post-mortem debugging via `cloud-init-output.log`.
- **Config validation**: The setup script validates `openclaw.json` with
  `jq empty` before starting the service, failing fast with the file contents
  on error.

## Summary of Deviations from Default OpenClaw Setup

| Area | Default guide | Our approach | Why |
|------|--------------|--------------|-----|
| Authentication | Shared gateway token | Cognito + ALB + trusted-proxy | Multi-user, no token in browser |
| Node.js install | `curl \| bash` | APT repo with GPG key | Supply chain protection |
| Ollama install | `curl \| sh` | Direct binary tarball | No arbitrary script execution |
| OpenClaw install | `npm install -g` (root) | Local npm install (user) | Least privilege |
| Systemd `ProtectHome` | `read-only` | `tmpfs` + `BindPaths` | Filesystem isolation |
| Config secrets | Inline in config file | Secrets Manager + env vars | No plaintext in userdata |
| Gateway bind | `loopback` | `lan` + `trustedProxies` | ALB needs network access |
| Proxy trust | Not configured | ALB subnet CIDRs (auto-derived) | Header forgery protection |
