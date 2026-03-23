#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this script as root." >&2
  exit 1
fi

install -m 644 /opt/openclaw/deploy/logrotate/openclaw /etc/logrotate.d/openclaw

if systemctl list-unit-files | grep -q '^logrotate.timer'; then
  systemctl enable --now logrotate.timer
fi

echo "Installed /etc/logrotate.d/openclaw"
