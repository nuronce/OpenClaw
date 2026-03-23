# OpenClaw AWS Deployment Repo

This repo is a reusable deployment scaffold for running OpenClaw on a single ARM64 EC2 instance with the recommended host install, Slack integration, and Anthropic Claude `setup-token` auth.

## Architecture Summary

- Compute: one `t4g.medium` EC2 instance on Amazon Linux 2023 ARM64
- Runtime: host-installed OpenClaw gateway
- Slack: Socket Mode, so Slack connects over an outbound WebSocket and no public inbound webhook endpoint is required
- Model access: Anthropic Claude `setup-token` stored in OpenClaw state on persistent host storage
- Storage: OpenClaw state under `/srv/openclaw` on persistent EBS-backed storage
- Operations: SSM for admin access, no public admin ports by default
- Logging: short local rotation, CloudWatch ingestion, daily S3 archival
- Migration path: gateway config stays file-based and portable

## Repo Structure

```text
aws/
  cloudwatch/
  iam/
  network/
  openclaw-foundation.yaml
deploy/
  cron/
  logrotate/
  openclaw/
docs/
scripts/
slack/
Requirements & Memory/
```

## Start Here

1. Provision AWS from `docs/aws-setup.md` using the foundation stack in either `create` or `existing` network mode.
2. Configure Claude from `docs/anthropic-claude-setup.md`.
3. Configure Slack from `docs/slack-app-setup-checklist.md`.
4. Install the OpenClaw config from `deploy/openclaw/openclaw.json`.
5. Fill in `deploy/.env.example` as `deploy/.env`.
6. Use `docs/runbook.md` for deploy, restart, and operations.

## Git CI/CD

- `DEPLOY_ENV_FILE` is written to `/opt/openclaw/deploy/.env` on the EC2 host over SSM.
- Set GitHub secrets for `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`, and `DEPLOY_ENV_FILE`.
- `AWS_REGION` should be set explicitly for the target deployment region; this repo no longer assumes a default region.

`DEPLOY_ENV_FILE` should contain the full contents of `deploy/.env`. Update it with:

```powershell
.\scripts\update-github-secrets.bat
```

## Optional SSH Access

This repo prefers SSM. If you also want SSH:

- open port 22 with the stack parameter `SshAccessCidr`
- set `KEY_PAIR_NAME` in `deploy/.env` so host bootstrap can install the matching EC2 public key
- use `SSH_ACCESS_HOSTNAME` in `deploy/.env` for whatever hostname or IP your team uses to connect

Example EC2 key-pair import:

```powershell
aws ec2 import-key-pair `
  --region <your-region> `
  --key-name openclaw-admin `
  --public-key-material fileb://C:\Users\<you>\.ssh\openclaw-admin.pub
```

Example `deploy/.env` values for SSH:

- `KEY_PAIR_NAME=openclaw-admin`
- `SSH_ACCESS_HOSTNAME=ec2-203-0-113-10.compute.amazonaws.com`

SSH login example:

```powershell
ssh -i C:\Users\<you>\.ssh\openclaw-admin ec2-user@<InstancePublicIp>
```
