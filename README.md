# OpenClaw AWS Deployment Repo

This repo is a reusable deployment scaffold for running OpenClaw on a single ARM64 EC2 instance with the recommended host install, Slack integration, and Anthropic Claude `setup-token` auth.

## Architecture Summary

- Compute: one `t4g.small` EC2 instance on Amazon Linux 2023 ARM64 by default
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

## ARM64 Sizing

The foundation stack now defaults to `t4g.small` to reduce baseline cost. If the workload needs more headroom, override the `InstanceType` parameter at deploy time.

Official AWS references for ARM64 EC2 choices and pricing:

- ARM64-capable EC2 families and specs: `https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instance-types.html`
- AWS Graviton overview: `https://aws.amazon.com/ec2/graviton/level-up-with-graviton/`
- T4g instance family details: `https://aws.amazon.com/ec2/instance-types/t4/`
- EC2 On-Demand pricing: `https://aws.amazon.com/ec2/pricing/on-demand/`
- AWS Pricing Calculator: `https://calculator.aws/`

## Git CI

- GitHub Actions in this repo are validation-only.
- CI runs linting and template or JSON validation on pushes, pull requests, and manual workflow runs.
- CI does not deploy infrastructure, write to AWS, provision hosts, or sync `deploy/.env`.
- Deployments are intentionally manual using the AWS CLI and the steps in `docs/aws-setup.md`.

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
