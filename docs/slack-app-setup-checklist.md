# Slack App Setup Checklist

## Recommended Setup Pattern

Create one Slack app per bot deployment. For Phase 1, examples include:

- `OpenClaw Marketing`
- `OpenClaw CX`

Why separate apps:

- cleaner permission boundaries
- easier revocation
- clearer audit trail
- simpler later handoff to separate services if the platform grows

## Use Socket Mode

Use Slack Socket Mode for Phase 1.

Reason:

- no public webhook endpoint required
- fits the private EC2 design
- keeps inbound security surface near zero

Slack documents that Socket Mode lets an app receive events without a public HTTP Request URL, using a WebSocket connection instead. Source: https://api.slack.com/apis/socket-mode

## Checklist

### 1. Create the App

- Go to `https://api.slack.com/apps`
- Click `Create New App`
- Choose `From an app manifest`
- Pick the target workspace
- Paste `slack/slack-app-manifest.yaml`
- The provided manifest defaults to `OpenClaw`; rename it before creation if you want deployment-specific branding

### 2. Enable App Home Messages

- Open `App Home`
- Turn on `Messages Tab`
- Allow users to send direct messages to the app

Slack notes that App Home messaging requires `chat:write`, and `im:history` is used to respond to messages. Source: https://api.slack.com/surfaces/tabs

### 3. Enable Socket Mode

- Open `Socket Mode`
- Turn it on
- Do not configure a public Request URL

### 4. Create the App-Level Token

- Open `Basic Information`
- Under `App-Level Tokens`, click `Generate Token and Scopes`
- Name it `socket-mode`
- Add the `connections:write` scope
- Save the token value as `SLACK_APP_TOKEN`

### 5. Review the Manifest Scopes

The bundled manifest includes the scopes already used by this repo's current Slack configuration, including:

- direct message and multiparty message access
- app mentions
- channel and group history read scopes
- directory lookup scopes used by the app

If you trim scopes later, keep the ones your deployment actually needs.

### 6. Confirm Event Subscriptions

The provided manifest enables these bot events:

- `app_mention`
- `message.channels`
- `message.groups`
- `message.im`
- `message.mpim`

If you reduce the event set later, make sure it stays aligned with the scopes and behaviors your deployment expects.

### 7. Install the App

- Open `OAuth & Permissions`
- Click `Install to Workspace`
- Approve the requested scopes
- Save the Bot User OAuth Token as `SLACK_BOT_TOKEN`

### 8. Restrict How the Team Uses It

- Ask the team to use the bot only in the Slack locations you intentionally support
- Do not grant additional scopes beyond the bundled manifest unless a real use case requires them
- If you want a DM-only deployment, trim the broader channel and group scopes and event subscriptions before app creation

## Exact Values to Put in `deploy/.env`

For each bot deployment, set:

```text
SLACK_BOT_TOKEN=xoxb-...
SLACK_APP_TOKEN=xapp-...
```

## Recommended Naming

- Marketing: `openclaw-marketing`
- CX: `openclaw-cx`
- Ops: `openclaw-ops`
- Tech: `openclaw-tech`
- Monetization: `openclaw-monetization`
- CoS: `openclaw-cos`
