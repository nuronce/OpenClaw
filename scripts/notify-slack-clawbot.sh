#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${OPENCLAW_ENV_FILE:-/opt/openclaw/deploy/.env}"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing env file: ${ENV_FILE}" >&2
  exit 1
fi

get_env_value() {
  local key="$1"
  awk -F= -v search="${key}" '$1 == search {print substr($0, index($0, "=") + 1); exit}' "${ENV_FILE}"
}

SLACK_BOT_TOKEN="$(get_env_value SLACK_BOT_TOKEN)"
SLACK_ALERT_USER_ID="$(get_env_value SLACK_ALERT_USER_ID)"
SLACK_ALLOWED_USER_IDS="$(get_env_value SLACK_ALLOWED_USER_IDS)"
RECIPIENT_MODE="${OPENCLAW_NOTIFY_RECIPIENTS:-allowlist}"

: "${SLACK_BOT_TOKEN:?SLACK_BOT_TOKEN must be set}"
: "${SLACK_ALERT_USER_ID:?SLACK_ALERT_USER_ID must be set}"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <message>" >&2
  exit 1
fi

MESSAGE="$*"

if [[ -z "${SLACK_ALLOWED_USER_IDS}" ]]; then
  SLACK_ALLOWED_USER_IDS="${SLACK_ALERT_USER_ID}"
fi

if [[ "${RECIPIENT_MODE}" == "alert" ]]; then
  recipient_ids=("${SLACK_ALERT_USER_ID}")
else
  mapfile -t recipient_ids < <(
    printf '%s' "${SLACK_ALLOWED_USER_IDS}" \
      | tr ',' '\n' \
      | awk '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0); if (length($0) > 0 && !seen[$0]++) print $0}'
  )
fi

if [[ "${#recipient_ids[@]}" -eq 0 ]]; then
  echo "No recipients resolved from SLACK_ALLOWED_USER_IDS." >&2
  exit 1
fi

sent_count=0

for recipient_id in "${recipient_ids[@]}"; do
  OPEN_JSON="$(curl -fsS https://slack.com/api/conversations.open \
    -H "Authorization: Bearer ${SLACK_BOT_TOKEN}" \
    -H "Content-Type: application/json; charset=utf-8" \
    --data "$(jq -nc --arg users "${recipient_id}" '{users: $users}')")"

  if [[ "$(jq -r '.ok' <<<"${OPEN_JSON}")" != "true" ]]; then
    echo "conversations.open failed for ${recipient_id}: ${OPEN_JSON}" >&2
    continue
  fi

  CHANNEL_ID="$(jq -r '.channel.id' <<<"${OPEN_JSON}")"
  POST_JSON="$(curl -fsS https://slack.com/api/chat.postMessage \
    -H "Authorization: Bearer ${SLACK_BOT_TOKEN}" \
    -H "Content-Type: application/json; charset=utf-8" \
    --data "$(jq -nc --arg channel "${CHANNEL_ID}" --arg text "${MESSAGE}" '{channel: $channel, text: $text}')")"

  if [[ "$(jq -r '.ok' <<<"${POST_JSON}")" != "true" ]]; then
    echo "chat.postMessage failed for ${recipient_id}: ${POST_JSON}" >&2
    continue
  fi

  sent_count=$((sent_count + 1))
done

if [[ "${sent_count}" -eq 0 ]]; then
  echo "Failed to deliver Slack notification to all recipients." >&2
  exit 1
fi
