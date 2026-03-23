#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -eq 0 ]]; then
  echo "Run this script as a non-root user such as ec2-user." >&2
  exit 1
fi

curl -fsSL https://openclaw.ai/install.sh | bash

echo "OpenClaw installed."
echo "Next steps:"
echo "1. Run: openclaw onboard --install-daemon"
echo "2. Run: sudo /opt/openclaw/scripts/install-openclaw-config.sh"
echo "3. Run: openclaw gateway status"
