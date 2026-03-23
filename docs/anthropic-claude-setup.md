# Anthropic Claude Setup

This deployment uses Anthropic `setup-token` auth for Claude subscription access.

OpenClaw documents the Anthropic subscription flow as:

1. run `claude setup-token`
2. run `openclaw models auth setup-token --provider anthropic`

Sources:

- https://docs.openclaw.ai/anthropic
- https://docs.openclaw.ai/gateway/authentication

## 1. Pick the Claude Models

For Phase 1, use:

```text
OPENCLAW_MODEL_PRIMARY=anthropic/claude-sonnet-4-20250514
OPENCLAW_MODEL_FAST=anthropic/claude-haiku-4-5
OPENCLAW_MODEL_DEEP=anthropic/claude-opus-4-1
```

OpenClaw’s Anthropic docs show the model is configured normally even when auth is `setup-token`. Source: https://docs.openclaw.ai/anthropic

This repo now exposes:

- `balanced` -> `OPENCLAW_MODEL_PRIMARY`
- `fast` -> `OPENCLAW_MODEL_FAST`
- `deep` -> `OPENCLAW_MODEL_DEEP`

Keep Sonnet as the default. Use Haiku for cheap/fast work and Opus for heavier reasoning.

This repo also installs a workspace `AGENTS.md` routing policy so OpenClaw can choose between the default model and targeted subagents by task type:

- `fast` subagent for quick low-cost work
- `deep` subagent for expensive/high-judgment work
- default `balanced` model for normal requests

## 2. Put the Values in `deploy/.env`

Set:

```text
AWS_REGION=<your-region>
OPENCLAW_MODEL_PRIMARY=anthropic/claude-sonnet-4-20250514
OPENCLAW_MODEL_FAST=anthropic/claude-haiku-4-5
OPENCLAW_MODEL_DEEP=anthropic/claude-opus-4-1
```

OpenClaw reads the runtime config from `/srv/openclaw/app/.openclaw/openclaw.json`.

## 3. Install OpenClaw on the EC2 Host

Run as `ec2-user`:

```bash
runuser -l ec2-user -c 'cd /opt/openclaw && bash scripts/install-openclaw-recommended.sh'
runuser -l ec2-user -c 'openclaw onboard --install-daemon'
```

## 4. Install and Log In to Claude Code on the EC2 Host

Run as `ec2-user`:

```bash
runuser -l ec2-user -c 'cd /opt/openclaw && bash scripts/install-claude-code.sh'
runuser -l ec2-user -c 'claude'
```

Complete the browser login first.

## 5. Run the Auth Flow on the EC2 Host

```bash
runuser -l ec2-user -c 'claude setup-token'
sudo /opt/openclaw/scripts/setup-anthropic-subscription-auth.sh
```

This runs:

```bash
openclaw models auth setup-token --provider anthropic
```

## 6. Verify

```bash
runuser -l ec2-user -c 'openclaw gateway status'
runuser -l ec2-user -c 'openclaw models status'
```

## 7. Notes

- token state persists in `/srv/openclaw/app/.openclaw`
- if the token expires, rerun the same two commands
- if Anthropic rejects this auth for your account, switch back to API key auth
- in Slack, keep Sonnet as the default and switch with `/model fast`, `/model deep`, or `/model balanced`
- automatic task routing in this repo is implemented by OpenClaw workspace instructions plus subagent config, not by a standalone provider-side router
