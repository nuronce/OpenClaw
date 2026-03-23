#!/usr/bin/env bash
set -euo pipefail

runuser -l ec2-user -c 'openclaw models auth setup-token --provider anthropic'
