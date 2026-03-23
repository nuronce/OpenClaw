#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="/opt/openclaw/deploy/.env"
NOTIFY_SCRIPT="/opt/openclaw/scripts/notify-slack-clawbot.sh"
MEMORY_DIR="/srv/openclaw/app/.openclaw/memory"
MEMORY_FILE="${MEMORY_DIR}/slack_allowed_users.json"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing env file: ${ENV_FILE}" >&2
  exit 1
fi

get_env_value() {
  local key="$1"
  awk -F= -v search="${key}" '$1 == search {print substr($0, index($0, "=") + 1); exit}' "${ENV_FILE}"
}

SLACK_BOT_TOKEN="$(get_env_value SLACK_BOT_TOKEN)"
SLACK_ALLOWED_USER_IDS="$(get_env_value SLACK_ALLOWED_USER_IDS)"
SLACK_ALERT_USER_ID="$(get_env_value SLACK_ALERT_USER_ID)"

: "${SLACK_BOT_TOKEN:?SLACK_BOT_TOKEN must be set}"
: "${SLACK_ALERT_USER_ID:?SLACK_ALERT_USER_ID must be set}"

if [[ -z "${SLACK_ALLOWED_USER_IDS}" ]]; then
  SLACK_ALLOWED_USER_IDS="${SLACK_ALERT_USER_ID}"
fi

mapfile -t user_ids < <(
  printf '%s' "${SLACK_ALLOWED_USER_IDS}" \
    | tr ',' '\n' \
    | awk '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0); if (length($0) > 0 && !seen[$0]++) print $0}'
)

if [[ "${#user_ids[@]}" -eq 0 ]]; then
  echo "No Slack user IDs resolved from SLACK_ALLOWED_USER_IDS." >&2
  exit 1
fi

mkdir -p "${MEMORY_DIR}"

tmp_json="$(mktemp)"
tmp_lines="$(mktemp)"
timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

cleanup() {
  rm -f "${tmp_json}" "${tmp_lines}"
}
trap cleanup EXIT

for user_id in "${user_ids[@]}"; do
  response="$(curl -fsS --get "https://slack.com/api/users.info" \
    -H "Authorization: Bearer ${SLACK_BOT_TOKEN}" \
    --data-urlencode "user=${user_id}")"

  ok="$(jq -r '.ok // false' <<<"${response}")"
  if [[ "${ok}" != "true" ]]; then
    error_msg="$(jq -r '.error // "unknown_error"' <<<"${response}")"
    jq -nc \
      --arg id "${user_id}" \
      --arg error "${error_msg}" \
      --arg synced_at "${timestamp}" \
      '{id:$id, error:$error, synced_at:$synced_at}' >> "${tmp_json}"
    printf -- "- %s: error=%s\n" "${user_id}" "${error_msg}" >> "${tmp_lines}"
    continue
  fi

  real_name="$(jq -r '.user.profile.real_name // .user.real_name // ""' <<<"${response}")"
  display_name="$(jq -r '.user.profile.display_name // ""' <<<"${response}")"
  email="$(jq -r '.user.profile.email // ""' <<<"${response}")"

  jq -nc \
    --arg id "${user_id}" \
    --arg real_name "${real_name}" \
    --arg display_name "${display_name}" \
    --arg email "${email}" \
    --arg synced_at "${timestamp}" \
    '{id:$id, real_name:$real_name, display_name:$display_name, email:$email, synced_at:$synced_at}' >> "${tmp_json}"

  if [[ -n "${email}" ]]; then
    printf -- "- %s: %s (%s) <%s>\n" "${user_id}" "${real_name}" "${display_name}" "${email}" >> "${tmp_lines}"
  else
    printf -- "- %s: %s (%s) <email unavailable>\n" "${user_id}" "${real_name}" "${display_name}" >> "${tmp_lines}"
  fi
done

jq -cs --arg synced_at "${timestamp}" '{synced_at:$synced_at, users:.}' "${tmp_json}" > "${MEMORY_FILE}"
chown ec2-user:ec2-user "${MEMORY_FILE}" || true

message=$'Daily Slack allowlist sync completed.\n'
message+="File: ${MEMORY_FILE}"$'\n'
message+="Synced at: ${timestamp}"$'\n'
message+=$'\n'"Users:"$'\n'
message+="$(cat "${tmp_lines}")"

"${NOTIFY_SCRIPT}" "${message}"
echo "Wrote ${MEMORY_FILE}"
