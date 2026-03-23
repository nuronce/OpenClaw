#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this script as root." >&2
  exit 1
fi

ENV_FILE="/opt/openclaw/deploy/.env"
TARGET_ROOT="/srv/openclaw/app/.openclaw"
TARGET_CONFIG="${TARGET_ROOT}/openclaw.json"
HOME_LINK="/home/ec2-user/.openclaw"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing ${ENV_FILE}. Create deploy/.env first." >&2
  exit 1
fi

get_env_value() {
  local key="$1"
  awk -F= -v search="${key}" '$1 == search {print substr($0, index($0, "=") + 1); exit}' "${ENV_FILE}"
}

OPENCLAW_MODEL_PRIMARY="$(get_env_value OPENCLAW_MODEL_PRIMARY)"
OPENCLAW_MODEL_FAST="$(get_env_value OPENCLAW_MODEL_FAST)"
OPENCLAW_MODEL_DEEP="$(get_env_value OPENCLAW_MODEL_DEEP)"
OPENCLAW_PORT="$(get_env_value OPENCLAW_PORT)"
OPENCLAW_BIND_MODE="$(get_env_value OPENCLAW_BIND_MODE)"
SLACK_BOT_TOKEN="$(get_env_value SLACK_BOT_TOKEN)"
SLACK_APP_TOKEN="$(get_env_value SLACK_APP_TOKEN)"
SLACK_ALERT_USER_ID="$(get_env_value SLACK_ALERT_USER_ID)"
SLACK_ALLOWED_USER_IDS="$(get_env_value SLACK_ALLOWED_USER_IDS)"
ASANA_PERSONAL_ACCESS_TOKEN="$(get_env_value ASANA_PERSONAL_ACCESS_TOKEN)"
GITHUB_PERSONAL_ACCESS_TOKEN="$(get_env_value GITHUB_PERSONAL_ACCESS_TOKEN)"
NOTION_API_KEY="$(get_env_value NOTION_API_KEY)"

: "${OPENCLAW_MODEL_PRIMARY:?OPENCLAW_MODEL_PRIMARY must be set}"
: "${OPENCLAW_MODEL_FAST:?OPENCLAW_MODEL_FAST must be set}"
: "${OPENCLAW_MODEL_DEEP:?OPENCLAW_MODEL_DEEP must be set}"
: "${OPENCLAW_PORT:?OPENCLAW_PORT must be set}"
: "${OPENCLAW_BIND_MODE:?OPENCLAW_BIND_MODE must be set}"
: "${SLACK_BOT_TOKEN:?SLACK_BOT_TOKEN must be set}"
: "${SLACK_APP_TOKEN:?SLACK_APP_TOKEN must be set}"
: "${SLACK_ALERT_USER_ID:?SLACK_ALERT_USER_ID must be set}"

if [[ -z "${SLACK_ALLOWED_USER_IDS}" ]]; then
  SLACK_ALLOWED_USER_IDS="${SLACK_ALERT_USER_ID}"
fi

SLACK_ALLOW_FROM_JSON="$(
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

if [[ "${SLACK_ALLOW_FROM_JSON}" = "[]" ]]; then
  echo "SLACK_ALLOWED_USER_IDS resolved to empty list; provide at least one Slack user ID." >&2
  exit 1
fi

export OPENCLAW_MODEL_PRIMARY OPENCLAW_MODEL_FAST OPENCLAW_MODEL_DEEP OPENCLAW_PORT OPENCLAW_BIND_MODE SLACK_BOT_TOKEN SLACK_APP_TOKEN SLACK_ALERT_USER_ID SLACK_ALLOW_FROM_JSON ASANA_PERSONAL_ACCESS_TOKEN GITHUB_PERSONAL_ACCESS_TOKEN NOTION_API_KEY

install -d -m 755 "${TARGET_ROOT}"
install -d -m 755 "${TARGET_ROOT}/workspace"
install -d -m 755 "${TARGET_ROOT}/agents"
install -d -m 755 "${TARGET_ROOT}/credentials"
install -d -m 755 "${TARGET_ROOT}/mcp"
install -d -m 755 "${TARGET_ROOT}/mcp/servers.d"
install -d -m 755 "${TARGET_ROOT}/workspace/skills"
install -d -m 755 "${TARGET_ROOT}/workspace/memory"

render_envsubst_file() {
  local source_path="$1"
  local target_path="$2"
  local tmp_file

  tmp_file="$(mktemp)"
  envsubst < "${source_path}" > "${tmp_file}"
  mv "${tmp_file}" "${target_path}"
}

render_envsubst_file /opt/openclaw/deploy/openclaw/openclaw.json "${TARGET_CONFIG}"

for workspace_file in /opt/openclaw/deploy/openclaw/workspace/*.md; do
  target_path="${TARGET_ROOT}/workspace/$(basename "${workspace_file}")"
  [[ -e "${workspace_file}" ]] || continue
  render_envsubst_file "${workspace_file}" "${target_path}"
done

if [[ -d /opt/openclaw/deploy/openclaw/workspace/skills ]]; then
  while IFS= read -r -d '' skill_file; do
    rel_path="${skill_file#/opt/openclaw/deploy/openclaw/workspace/skills/}"
    target_path="${TARGET_ROOT}/workspace/skills/${rel_path}"
    install -d -m 755 "$(dirname "${target_path}")"
    render_envsubst_file "${skill_file}" "${target_path}"
  done < <(find /opt/openclaw/deploy/openclaw/workspace/skills -type f -print0)
fi

if [[ -d /opt/openclaw/deploy/openclaw/mcp ]]; then
  while IFS= read -r -d '' mcp_file; do
    rel_path="${mcp_file#/opt/openclaw/deploy/openclaw/mcp/}"
    target_path="${TARGET_ROOT}/mcp/${rel_path}"
    install -d -m 755 "$(dirname "${target_path}")"
    render_envsubst_file "${mcp_file}" "${target_path}"
  done < <(find /opt/openclaw/deploy/openclaw/mcp -type f -print0)
fi

if [[ -f "${TARGET_ROOT}/mcp/mcpservers.json" ]]; then
  cp "${TARGET_ROOT}/mcp/mcpservers.json" "${TARGET_ROOT}/mcpservers.json"
fi

if [[ ! -e "${TARGET_ROOT}/workspace/MEMORY.md" ]]; then
  cat <<'EOF' > "${TARGET_ROOT}/workspace/MEMORY.md"
# Long-Term Memory

EOF
fi

daily_memory_path="${TARGET_ROOT}/workspace/memory/$(date +%F).md"
if [[ ! -e "${daily_memory_path}" ]]; then
  cat <<EOF > "${daily_memory_path}"
# $(date +%F)

EOF
fi

if [[ -e "${HOME_LINK}" && ! -L "${HOME_LINK}" ]]; then
  rm -rf "${HOME_LINK}"
fi

ln -sfn "${TARGET_ROOT}" "${HOME_LINK}"
chown -h ec2-user:ec2-user "${HOME_LINK}"
chown -R ec2-user:ec2-user "${TARGET_ROOT}"

echo "Installed OpenClaw config to ${TARGET_CONFIG}"
if [[ -f "${TARGET_ROOT}/mcpservers.json" ]]; then
  echo "Installed MCP config to ${TARGET_ROOT}/mcpservers.json"
  echo "Installed MCP config to ${TARGET_ROOT}/mcp/mcpservers.json"
fi
echo "Linked ${HOME_LINK} -> ${TARGET_ROOT}"
