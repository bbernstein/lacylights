# Migrate app.lacylights.com from ALB to Caddy

**Date:** 2026-03-03
**Status:** Approved
**Goal:** Eliminate the ALB (~$16-22/month) by replacing it with Caddy on the EC2 instance for automatic HTTPS via Let's Encrypt.

## Summary

The current `app.lacylights.com` architecture uses an Application Load Balancer for HTTPS termination, with nginx on EC2 as a reverse proxy to the Go backend and Next.js frontend. The ALB is the single most expensive component for the demo app.

This migration replaces both the ALB and nginx with Caddy, which handles HTTPS (via Let's Encrypt), HTTP-to-HTTPS redirects, reverse proxying, and WebSocket upgrades in a single binary with minimal configuration.

### Before

```
Internet -> Route 53 -> ALB (HTTPS/443) -> EC2 (nginx :80) -> Go (:4000) / Next.js (:3000)
```

### After

```
Internet -> Route 53 -> EC2 (Caddy :443) -> Go (:4000) / Next.js (:3000)
```

## What Gets Removed

| Resource | Location | Reason |
|----------|----------|--------|
| ALB (load balancer, security group, target group, listeners) | `modules/alb/` directory | Caddy replaces HTTPS termination |
| ALB target group attachment | `modules/ec2-webapp/main.tf:166-170` | No ALB to register with |
| ACM certificate for app.lacylights.com | `module "acm_app"` in `main.tf` | Caddy uses Let's Encrypt |
| Route 53 ALB alias module | `modules/route53-alb/` directory | DNS points to EC2 EIP instead |
| AZ instance type filtering | `data "aws_ec2_instance_type_offerings"` + `locals` in `main.tf` | Only needed for multi-AZ ALB |
| nginx installation and config | `modules/ec2-webapp/templates/user-data.sh` | Replaced by Caddy |

### Modules deleted entirely

- `modules/alb/` (main.tf, variables.tf, outputs.tf)
- `modules/route53-alb/` (main.tf, variables.tf, outputs.tf)

## What Changes

### 1. EC2 Security Group (`modules/ec2-webapp/main.tf`)

**Before:** Allows HTTP (80) only from ALB security group.

**After:** Allows HTTP (80) and HTTPS (443) from `0.0.0.0/0`. Caddy listens directly on the internet.

Remove `alb_security_group_id` variable and `target_group_arn` variable. Remove `aws_lb_target_group_attachment` resource.

### 2. Elastic IP Becomes Required

Caddy needs a stable public IP for Let's Encrypt certificate issuance, and Route 53 needs a stable A record target. Change `enable_eip` default to `true` in the ec2-webapp module.

### 3. User-Data Script — Replace nginx with Caddy

Remove nginx installation. Install Caddy from the official Caddy COPR repo for Amazon Linux.

The Caddyfile replaces the entire nginx configuration:

```
app.lacylights.com {
    handle /graphql {
        reverse_proxy localhost:4000
    }
    handle /ws {
        reverse_proxy localhost:4000/graphql
    }
    handle /health {
        reverse_proxy localhost:4000/health
    }
    handle {
        reverse_proxy localhost:3000
    }
}
```

Caddy automatically handles:
- HTTPS certificate provisioning and renewal (Let's Encrypt)
- HTTP (80) to HTTPS (443) redirect
- WebSocket protocol upgrades (transparent, no config needed)
- Reasonable timeouts for long-lived connections

### 4. DNS Record

**Before:** Route 53 A record (alias) pointing to ALB DNS name, via `modules/route53-alb/`.

**After:** Route 53 A record pointing to the EC2 Elastic IP. Use a simple `aws_route53_record` resource directly in the ec2-webapp module or main.tf.

### 5. main.tf Simplification

The app demo section in `main.tf` simplifies significantly:

**Remove:**
- `data "aws_availability_zones"` — only needed for multi-AZ ALB
- `data "aws_ec2_instance_type_offerings"` — only needed for AZ filtering
- `locals { supported_azs }` — only needed for AZ filtering
- `module "acm_app"` — Caddy handles certs
- `module "alb_app"` — eliminated
- `module "route53_app"` (route53-alb) — replaced with simple A record

**Simplify:**
- `data "aws_vpc"` and `data "aws_subnets"` — keep but simplify (no AZ filtering needed)
- `module "ec2_app"` — remove ALB-related parameters (`alb_security_group_id`, `target_group_arn`)

**Add:**
- Route 53 A record pointing to EC2 EIP (either inline or via existing `route53` module adapted for IP targets)

### 6. Outputs Cleanup (`outputs.tf`)

- Remove `app_alb_dns_name` output
- Keep `app_url`, `app_ec2_instance_id`, `app_ec2_public_ip`

### 7. Variables Cleanup (`variables.tf`)

- Change `app_enable_eip` default from `false` to `true`
- No new variables needed

### 8. Scripts Updates

**`scripts/deploy-app.sh`:**
- Replace all `nginx` references with `caddy`
- `--init` action: install Caddy instead of nginx, write Caddyfile instead of nginx config
- `--restart` action: restart `caddy` instead of `nginx`
- `--status` action: check `caddy` status instead of `nginx`

**`scripts/ssh-app.sh`:** No changes needed.

### 9. Documentation Updates

- Update `CLAUDE.md` to reflect Caddy instead of ALB+nginx in the architecture tables
- Update `docs/INFRASTRUCTURE_PLAN.md` if it exists

## Migration Strategy

This is a **destructive migration** — the ALB and ACM cert will be destroyed by terraform. The recommended approach:

1. Apply terraform changes (destroys ALB, updates EC2 security group, creates EIP)
2. The EC2 instance will be **replaced** (user-data changes trigger replacement)
3. Route 53 record switches from ALB to EIP
4. Caddy obtains Let's Encrypt certificate on first startup
5. Brief downtime expected during the EC2 replacement (~5-10 minutes)

### Rollback

If something goes wrong:
- Revert the terraform changes and `terraform apply` to recreate the ALB
- The EC2 instance will be replaced again with the nginx-based user-data

## Cost Impact

| Component | Before | After |
|-----------|--------|-------|
| ALB (hourly + LCU) | ~$16-22/month | $0 |
| ACM certificate | $0 (free) | $0 (removed) |
| Elastic IP | $0 (not used) | $0 (attached to running instance = free) |
| EC2 t3.micro | ~$8.50/month | ~$8.50/month |
| **Total app cost** | **~$24-30/month** | **~$8.50/month** |

**Estimated savings: ~$16-22/month**
