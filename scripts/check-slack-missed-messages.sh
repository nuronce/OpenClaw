#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="/opt/openclaw/deploy/.env"
NOTIFY_SCRIPT="/opt/openclaw/scripts/notify-slack-clawbot.sh"
WINDOW_MINUTES="${SLACK_MISSED_MESSAGES_WINDOW_MINUTES:-30}"
MAX_ITEMS="${SLACK_MISSED_MESSAGES_MAX_ITEMS:-20}"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing ${ENV_FILE}; skipping missed Slack message check." >&2
  exit 0
fi

if [[ ! -x "${NOTIFY_SCRIPT}" ]]; then
  echo "Missing ${NOTIFY_SCRIPT}; skipping missed Slack message check." >&2
  exit 0
fi

get_env_value() {
  local key="$1"
  awk -F= -v search="${key}" '$1 == search {print substr($0, index($0, "=") + 1); exit}' "${ENV_FILE}"
}

SLACK_BOT_TOKEN="$(get_env_value SLACK_BOT_TOKEN)"
SLACK_ALLOWED_USER_IDS="$(get_env_value SLACK_ALLOWED_USER_IDS)"

if [[ -z "${SLACK_BOT_TOKEN}" ]]; then
  echo "SLACK_BOT_TOKEN is empty; skipping missed Slack message check." >&2
  exit 0
fi

if [[ -z "${SLACK_ALLOWED_USER_IDS}" ]]; then
  echo "SLACK_ALLOWED_USER_IDS is empty; skipping missed Slack message check." >&2
  exit 0
fi

if ! [[ "${WINDOW_MINUTES}" =~ ^[0-9]+$ ]]; then
  echo "SLACK_MISSED_MESSAGES_WINDOW_MINUTES must be an integer; got '${WINDOW_MINUTES}'." >&2
  exit 1
fi

if ! [[ "${MAX_ITEMS}" =~ ^[0-9]+$ ]]; then
  echo "SLACK_MISSED_MESSAGES_MAX_ITEMS must be an integer; got '${MAX_ITEMS}'." >&2
  exit 1
fi

if (( WINDOW_MINUTES <= 0 )); then
  echo "SLACK_MISSED_MESSAGES_WINDOW_MINUTES <= 0; skipping missed Slack message check."
  exit 0
fi

if (( MAX_ITEMS <= 0 )); then
  echo "SLACK_MISSED_MESSAGES_MAX_ITEMS <= 0; skipping missed Slack message check."
  exit 0
fi

SLACK_API_BASE="https://slack.com/api"
OLDEST_TS="$(date -u -d "-${WINDOW_MINUTES} minutes" +%s)"
NOW_TS="$(date -u +%s)"

slack_api_post() {
  local method="$1"
  local payload="$2"
  curl -fsS "${SLACK_API_BASE}/${method}" \
    -H "Authorization: Bearer ${SLACK_BOT_TOKEN}" \
    -H "Content-Type: application/json; charset=utf-8" \
    --data "${payload}"
}

sanitize_text() {
  tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g' | sed -E 's/^ +| +$//g'
}

human_ts() {
  local ts="$1"
  local sec="${ts%%.*}"
  date -d "@${sec}" '+%Y-%m-%d %I:%M:%S %p %Z'
}

declare -A USER_LABEL_CACHE

resolve_user_label() {
  local user_id="$1"
  if [[ -n "${USER_LABEL_CACHE[$user_id]+x}" ]]; then
    printf '%s' "${USER_LABEL_CACHE[$user_id]}"
    return 0
  fi

  local info_json label
  info_json="$(slack_api_post users.info "$(jq -nc --arg user "${user_id}" '{user: $user}')" || true)"
  if [[ "$(jq -r '.ok // false' <<<"${info_json}")" != "true" ]]; then
    USER_LABEL_CACHE["${user_id}"]="${user_id}"
    printf '%s' "${user_id}"
    return 0
  fi

  label="$(
    jq -r '
      .user.profile.display_name_normalized // .user.profile.display_name //
      .user.profile.real_name_normalized // .user.profile.real_name //
      .user.real_name // .user.name // empty
    ' <<<"${info_json}"
  )"

  if [[ -z "${label}" || "${label}" == "null" ]]; then
    label="${user_id}"
  fi

  USER_LABEL_CACHE["${user_id}"]="${label}"
  printf '%s' "${label}"
}

allowed_json="$(
  printf '%s' "${SLACK_ALLOWED_USER_IDS}" \
    | tr ',' '\n' \
    | awk '
      {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
        if (length($0) > 0) {
          gsub(/"/, "\\\"", $0)
          items[++n] = "\"" $0 "\""
        }
      }
      END {
        printf "["
        for (i = 1; i <= n; i++) {
          if (i > 1) printf ","
          printf "%s", items[i]
        }
        printf "]"
      }
    '
)"

if [[ "${allowed_json}" == "[]" ]]; then
  echo "No valid entries in SLACK_ALLOWED_USER_IDS; skipping missed Slack message check."
  exit 0
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT
events_file="${tmp_dir}/events.txt"
touch "${events_file}"

collect_from_channel() {
  local channel_id="$1"
  local channel_type="$2"
  local history_json history_ok

  history_json="$(slack_api_post conversations.history "$(jq -nc \
    --arg channel "${channel_id}" \
    --arg oldest "${OLDEST_TS}" \
    '{channel: $channel, oldest: $oldest, inclusive: false, limit: 200}')" || true)"
  history_ok="$(jq -r '.ok // false' <<<"${history_json}")"
  if [[ "${history_ok}" != "true" ]]; then
    return 0
  fi

  jq -r --arg type "${channel_type}" --argjson allowed "${allowed_json}" '
    .messages[]?
    | select(.user != null)
    | select((.subtype // "") == "")
    | select((.user as $u | $allowed | index($u)) != null)
    | "\($type)\t\(.user)\t\(.ts)\t\((.text // ""))"
  ' <<<"${history_json}" >> "${events_file}"
}

# DM channels for each allowed user (reliable, no pagination required).
while IFS= read -r user_id; do
  [[ -n "${user_id}" ]] || continue
  open_json="$(slack_api_post conversations.open "$(jq -nc --arg users "${user_id}" '{users: $users}')" || true)"
  if [[ "$(jq -r '.ok // false' <<<"${open_json}")" != "true" ]]; then
    continue
  fi
  channel_id="$(jq -r '.channel.id // empty' <<<"${open_json}")"
  [[ -n "${channel_id}" ]] || continue
  collect_from_channel "${channel_id}" "dm"
done < <(printf '%s' "${SLACK_ALLOWED_USER_IDS}" | tr ',' '\n' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')

# MPIM channels (single-page scan is enough for current workspace size).
mpim_list_json="$(slack_api_post conversations.list "$(jq -nc '{types:"mpim", exclude_archived:true, limit:200}')" || true)"
if [[ "$(jq -r '.ok // false' <<<"${mpim_list_json}")" == "true" ]]; then
  while IFS= read -r channel_id; do
    [[ -n "${channel_id}" ]] || continue
    collect_from_channel "${channel_id}" "mpim"
  done < <(jq -r '.channels[]?.id // empty' <<<"${mpim_list_json}")
fi

if [[ ! -s "${events_file}" ]]; then
  echo "No missed Slack user messages in the last ${WINDOW_MINUTES} minute(s)."
  exit 0
fi

summary_lines="$(
  sort -t$'\t' -k3,3n "${events_file}" \
    | awk -F'\t' '{print $0}' \
    | tail -n "${MAX_ITEMS}" \
    | while IFS=$'\t' read -r ctype uid ts text; do
        display_name="$(resolve_user_label "${uid}")"
        display_time="$(human_ts "${ts}")"
        safe_text="$(printf '%s' "${text}" | sanitize_text | cut -c1-120)"
        printf -- "- [%s] %s @ %s: %s\n" "${ctype}" "${display_name}" "${display_time}" "${safe_text}"
      done
)"

total_count="$(wc -l < "${events_file}" | tr -d '[:space:]')"
window_start_human="$(human_ts "${OLDEST_TS}")"
window_end_human="$(human_ts "${NOW_TS}")"
message="Slack catch-up after restart: found ${total_count} allowed-user message(s) between ${window_start_human} and ${window_end_human}."
if [[ -n "${summary_lines}" ]]; then
  message+=$'\n'"Most recent ${MAX_ITEMS}:"
  message+=$'\n'"${summary_lines}"
fi

OPENCLAW_NOTIFY_RECIPIENTS=alert "${NOTIFY_SCRIPT}" "${message}"
echo "Posted missed Slack message summary (${total_count} items)."
