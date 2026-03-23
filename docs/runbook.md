# Runbook

## Deploy

```bash
cd /opt/openclaw
cp deploy/.env.example deploy/.env
vi deploy/.env
sudo bash scripts/install-openclaw-config.sh
runuser -l ec2-user -c 'cd /opt/openclaw && bash scripts/install-openclaw-recommended.sh'
runuser -l ec2-user -c 'openclaw onboard --install-daemon'
runuser -l ec2-user -c 'cd /opt/openclaw && bash scripts/install-openclaw-skills.sh'
sudo bash scripts/install-logrotate-config.sh
sudo logrotate -f /etc/logrotate.conf
sudo systemctl daemon-reload
runuser -l ec2-user -c 'cd /opt/openclaw && bash scripts/install-claude-code.sh'
runuser -l ec2-user -c 'claude'
runuser -l ec2-user -c 'claude setup-token'
sudo /opt/openclaw/scripts/setup-anthropic-subscription-auth.sh
```

Verify:

```bash
runuser -l ec2-user -c 'openclaw gateway status'
```

Model switching from Slack:

```text
/model balanced
/model fast
/model deep
```

Automatic routing:

- normal requests stay on the default `balanced` model
- quick low-cost tasks are routed by OpenClaw to a `fast` subagent
- harder reasoning tasks are routed by OpenClaw to a `deep` subagent

Workspace instruction files:

- `/opt/openclaw/deploy/openclaw/workspace/*.md` are copied into `/srv/openclaw/app/.openclaw/workspace/`
- use these files for persistent instructions, policy, product context, and routing guidance for the live bot
- do not put deployment-repo authoring instructions there
- Slack messages are still the live user prompts

Installed ClawHub skills:

- default install: `asana`
- set `CLAWHUB_SKILLS` (comma/space separated) for ClawHub-installed skills
- `slack` and `healthcheck` are hardcoded stock skills (not env-driven)
- set `OPENCLAW_SKILLS` (comma/space separated) for additional stock OpenClaw skills you want to track in config/docs
- example: `CLAWHUB_SKILLS="asana summarize notion"`
- example: `OPENCLAW_SKILLS="github weather"`

Skill credentials:

- `ASANA_PERSONAL_ACCESS_TOKEN` is rendered into `skills.entries.asana.env`
- `GITHUB_PERSONAL_ACCESS_TOKEN` is rendered into `skills.entries.github.env` as `GH_TOKEN`/`GITHUB_TOKEN`
- `NOTION_API_KEY` is rendered into `skills.entries.notion.env`
- credentials come from `deploy/.env` at install time
- Slack DM allowlist comes from `SLACK_ALLOWED_USER_IDS` (comma-separated Slack user IDs).
- if `SLACK_ALLOWED_USER_IDS` is empty, deploy falls back to `SLACK_ALERT_USER_ID`.
- Deploy/health/boot notifications are sent to all IDs in `SLACK_ALLOWED_USER_IDS`.
- Slack missed-message catch-up notifications are sent only to `SLACK_ALERT_USER_ID`.
- Daily Slack allowlist sync script writes `/srv/openclaw/app/.openclaw/memory/slack_allowed_users.json`.
- For email capture from Slack profile, add bot scope `users:read.email` and reinstall the app.

Focus skills:

```text
/skill asana
/skill youtube-watcher
/skill self-improving-agent
/skill find-skills
/skill notion
/skill marketing
/skill cx
/skill ops
/skill tech
/skill monetization
/skill cos
/skill summarize
```

Optional self-improving-agent hook:

- source: `/opt/openclaw/skills/self-improving-agent/hooks/openclaw`
- destination: `~/.openclaw/hooks/self-improvement`
- enable with: `openclaw hooks enable self-improvement`

Provisioned helper binaries:

- `gh` via GitHub's RPM repo on Amazon Linux

Skill install transport:

- prefers `clawhub install <skill>` when `clawhub` exists on PATH
- falls back to `npx -y clawhub@latest install <skill>`

Post-install verification:

- `openclaw skills check` runs at the end of skill installation

## Restart

Restart the gateway:

```bash
runuser -l ec2-user -c 'openclaw gateway restart'
```

## Backup

Archive logs immediately:

```bash
sudo /opt/openclaw/scripts/archive-logs-to-s3.sh
```

Check the scheduled jobs:

```bash
sudo cat /etc/cron.d/openclaw-maintenance
systemctl status logrotate.timer
```

Run allowlist sync manually:

```bash
sudo /opt/openclaw/scripts/sync-slack-allowed-users.sh
cat /srv/openclaw/app/.openclaw/memory/slack_allowed_users.json
```

Run Slack missed-message catch-up manually:

```bash
sudo /opt/openclaw/scripts/check-slack-missed-messages.sh
```

Tuning knobs in `deploy/.env`:

- `SLACK_MISSED_MESSAGES_WINDOW_MINUTES` (default `30`)
- `SLACK_MISSED_MESSAGES_MAX_ITEMS` (default `20`)

## Health Checks

Recent logs:

```bash
runuser -l ec2-user -c 'openclaw logs --limit 200'
```
