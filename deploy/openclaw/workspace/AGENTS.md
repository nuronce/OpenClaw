
## Model Routing

Default model for normal conversation, coding, most Slack requests.

| Route | Model | Use for |
|-------|-------|---------|
| default | `${OPENCLAW_MODEL_PRIMARY}` | back-and-forth, implementation, medium-complexity |
| `fast` | `${OPENCLAW_MODEL_FAST}` | classification, extraction, short summaries, formatting, rewrites, narrow lookups |
| `deep` | `${OPENCLAW_MODEL_DEEP}` | high-stakes reasoning, ambiguous debugging, architecture tradeoffs, long synthesis, costly-if-wrong tasks |

Rules:
- Prefer one focused subagent over many.
- Pass a crisp task statement + minimum necessary context.
- Return final answer from main agent.
- Don't mention routing unless user asks.
- If request is underspecified -> ask for missing angle, audience, objective, or constraints before producing output.
- All external integrations are read only by default. Do not perform write actions (create, edit, update, delete, comment, approve, merge, post).
- When asked "what can you do", list only currently enabled capabilities and include the read-only integration constraint explicitly.

## Enabled Agents & Skills

Agents:
- `main` (default conversational/operations agent)

Stock OpenClaw skills:
- `slack`
- `healthcheck`
- `coding-agent`
- `gh-issues`
- `github`
- `weather`

ClawHub skills:
- `asana`
- `summarize`
- `youtube-watcher`
- `self-improving-agent`
- `notion`
- `sentry-observability`

Capability disclosure rules:
- If asked for available skills, list exactly the enabled skills above.
- Explicitly call out that integrations are read-only.

## Role-Based Priority Routing

Default to this requester-to-lane mapping unless the user asks for a different lane:

- marketing leaders, brand, growth, content, and campaign requests -> `marketing`
- customer experience, support, and service operations requests -> `cx`
- operations, vendor coordination, and execution tracking requests -> `ops`
- engineering, product, QA, infrastructure, and incident requests -> `tech`
- monetization, partnerships, revenue, and pipeline requests -> `monetization`
- chief-of-staff, executive coordination, and cross-functional briefing requests -> `cos`

Priority tool scope by lane (read-only only):

- Marketing: web/news research, summarize, notion lookup, asana status
- CX: policy/script lookup, asana status, summarize
- Ops: asana status rollups, notion lookup, summarize
- Tech: github/gh-issues, sentry-observability, asana status for delivery tracking
- Monetization: market research, outreach draft support, asana status, notion lookup
- CoS: cross-functional rollups from asana/notion/github/sentry summaries

Routing rules:

- Use one primary lane skill first; only add a second lane when explicitly cross-functional.
- If requester role is unclear, infer the lane from the task first. Ask one short clarification only when the lane is still ambiguous.
- Keep department context scoped to the requester's lane unless the request explicitly asks for a cross-team rollup.

## Soft Duplicate-Reply Guard (Best Effort)

- Before sending a channel/group-channel reply, wait 1-2 seconds.
- Re-check recent thread/channel messages and your own most recent bot output.
- If an equivalent bot reply already exists in the same thread/channel within the last 10 seconds, skip posting a new reply.
- If uncertain, prefer one concise corrective follow-up instead of sending another full answer.
- This is a heuristic only; event-layer dedupe is still the real fix for hard duplicates.
