## Deployment Memory

- Target runtime is Amazon Linux 2023 on EC2. Prefer portable shell patterns over newer GNU-specific flags unless verified on Amazon Linux first.
- `envsubst` on Amazon Linux may not support options like `--input`. Use standard redirection with a temp file if needed.
- GitHub Actions deploys use the `DEPLOY_ENV_FILE` secret. That secret can lag behind `deploy/.env.example`, so deploy scripts should be backward compatible with missing newer vars when reasonable.
- When adding new required env vars, prefer safe defaults or compatibility fallbacks in install scripts to avoid breaking existing deploy secrets.
- Validate deployment assumptions against the host environment, not just the local workstation.
- OpenClaw runs on the Amazon Linux EC2 host, not in local PowerShell. PowerShell is only used to open SSM or SSH sessions to the host.
- Skill env keys are now split and explicit:
  - `CLAWHUB_SKILLS` for ClawHub-installed skills.
  - `OPENCLAW_SKILLS` for stock OpenClaw skills (tracking/intent).
  - No backward compatibility alias for `OPENCLAW_REQUIRED_SKILLS`.
- Current deployment identifiers such as instance ID, IP addresses, subnet IDs, and region are runtime-specific.
- Read them from the active CloudFormation stack outputs, AWS CLI, or the current `deploy/.env` rather than hardcoding them into repo guidance.
- Preferred connection method from Windows is AWS SSM from PowerShell, then run Linux commands on the host shell.
- For private GitHub Actions troubleshooting, pull logs directly with:
  - `gh run view <run_id> --job <job_id> --log`
  - Prefer this over waiting for screenshots.
- If SSH is enabled, use a command shaped like `ssh -i <private-key-path> ec2-user@<InstancePublicIp>`.
