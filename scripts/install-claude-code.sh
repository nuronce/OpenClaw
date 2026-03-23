#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -eq 0 ]]; then
  echo "Run this script as a non-root user such as ec2-user." >&2
  exit 1
fi

curl -fsSL https://claude.ai/install.sh | bash

# Ink-based commands require a real TTY. SSM/AWS-RunShellScript is non-interactive,
# so skip doctor there to avoid "raw mode is not supported" noise/failures.
if [[ -t 0 && -t 1 ]]; then
  claude doctor || true
else
  echo "Skipping 'claude doctor' in non-interactive shell (no TTY)."
fi

echo "Claude Code installed."
echo "Next steps:"
echo "1. Run: claude"
echo "2. Complete login in the browser."
echo "3. Run: claude setup-token"
echo "4. Run: sudo /opt/openclaw/scripts/setup-anthropic-subscription-auth.sh"
