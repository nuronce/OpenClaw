#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this script as root." >&2
  exit 1
fi

# Remove any preinstalled Amazon Linux/NodeSource Node packages before
# OpenClaw's installer pulls the target Node runtime.
dnf remove -y \
  nodejs \
  nodejs-full-i18n \
  nodejs-npm \
  npm \
  libnode \
  nsolid \
  nsolid-npm \
  nodesource-release-el9 \
  'nodejs-*' \
  'nsolid-*' \
  2>/dev/null || true
dnf clean all >/dev/null 2>&1 || true

dnf update -y
dnf install -y \
  amazon-cloudwatch-agent \
  awscli \
  cronie \
  dnf-plugins-core \
  gettext \
  git \
  jq \
  logrotate \
  unzip

dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo || true
dnf install -y gh || true

systemctl enable --now crond
systemctl enable --now amazon-ssm-agent || true

loginctl enable-linger ec2-user || true

mkdir -p /etc/openclaw
mkdir -p /opt/openclaw
mkdir -p /srv/openclaw/app
mkdir -p /srv/openclaw/app/.openclaw/workspace
mkdir -p /srv/openclaw/app/.openclaw/agents
mkdir -p /srv/openclaw/app/.openclaw/credentials
mkdir -p /var/log/openclaw/archive
mkdir -p /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.d

chown -R ec2-user:ec2-user /opt/openclaw || true
chown -R ec2-user:ec2-user /srv/openclaw || true
chown -R root:root /var/log/openclaw || true

echo "Bootstrap complete."
echo "Next steps:"
echo "1. Copy this repo to /opt/openclaw if you have not already."
echo "2. Create /opt/openclaw/deploy/.env from .env.example."
echo "3. Install OpenClaw as ec2-user with scripts/install-openclaw-recommended.sh."
echo "4. Install Claude Code as ec2-user with scripts/install-claude-code.sh."
echo "5. Run openclaw onboard --install-daemon as ec2-user."
echo "6. Install /srv/openclaw/app/.openclaw/openclaw.json with scripts/install-openclaw-config.sh."
echo "7. Install log rotation with scripts/install-logrotate-config.sh."
echo "8. Install the CloudWatch config."
