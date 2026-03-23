#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -eq 0 ]]; then
  echo "Run this script as a non-root user such as ec2-user." >&2
  exit 1
fi

DEFAULT_CLAWHUB_SKILLS="asana"
HARDCODED_OPENCLAW_SKILLS_RAW="slack healthcheck"
CLAWHUB_SKILLS_RAW="${CLAWHUB_SKILLS:-}"
OPENCLAW_SKILLS_RAW="${OPENCLAW_SKILLS:-}"

normalize_skills_list() {
  printf '%s' "$1" \
    | tr ',;' '  ' \
    | xargs -n1 \
    | awk 'NF && !seen[$0]++'
}

icon_for_skill() {
  case "$1" in
    slack) echo "💬" ;;
    healthcheck) echo "📦" ;;
    github) echo "🐙" ;;
    gh-issues) echo "📦" ;;
    weather) echo "☔" ;;
    coding-agent) echo "🧩" ;;
    asana) echo "📋" ;;
    summarize) echo "🧾" ;;
    youtube-watcher) echo "📺" ;;
    self-improving-agent) echo "🧠" ;;
    notion) echo "📝" ;;
    sentry-observability) echo "🚨" ;;
    *) echo "🧩" ;;
  esac
}

format_skills_with_icons() {
  if [[ "$#" -eq 0 ]]; then
    echo "none"
    return
  fi

  local out=""
  local skill icon
  for skill in "$@"; do
    icon="$(icon_for_skill "${skill}")"
    if [[ -n "${out}" ]]; then
      out+=", "
    fi
    out+="${icon} ${skill}"
  done
  echo "${out}"
}

if [[ -z "${CLAWHUB_SKILLS_RAW}" ]]; then
  CLAWHUB_SKILLS_RAW="${DEFAULT_CLAWHUB_SKILLS}"
fi

mapfile -t clawhub_skills < <(normalize_skills_list "${CLAWHUB_SKILLS_RAW}" || true)
mapfile -t openclaw_skills < <(
  normalize_skills_list "${HARDCODED_OPENCLAW_SKILLS_RAW} ${OPENCLAW_SKILLS_RAW}" || true
)

if ! command -v openclaw >/dev/null 2>&1; then
  echo "openclaw is not installed or not on PATH." >&2
  exit 1
fi

get_deploy_env_value() {
  local key="$1"
  local env_file="/opt/openclaw/deploy/.env"
  if [[ ! -f "${env_file}" ]]; then
    return 1
  fi
  awk -F= -v search="${key}" '$1 == search {print substr($0, index($0, "=") + 1); exit}' "${env_file}"
}

configure_github_cli_auth() {
  local github_pat="${GITHUB_PERSONAL_ACCESS_TOKEN:-}"

  if [[ -z "${github_pat}" ]]; then
    github_pat="$(get_deploy_env_value GITHUB_PERSONAL_ACCESS_TOKEN || true)"
  fi

  if [[ -z "${github_pat}" ]]; then
    echo "GITHUB_PERSONAL_ACCESS_TOKEN is not set; skipping gh auth provisioning."
    return 0
  fi

  if ! command -v gh >/dev/null 2>&1; then
    echo "gh CLI not found; skipping gh auth provisioning."
    return 0
  fi

  if printf '%s' "${github_pat}" | gh auth login --hostname github.com --with-token >/dev/null 2>&1; then
    echo "Configured gh auth for github.com."
  else
    echo "Failed to configure gh auth with GITHUB_PERSONAL_ACCESS_TOKEN." >&2
    return 1
  fi
}

configure_github_cli_auth

install_skill() {
  local skill="$1"
  local output

  run_install_cmd() {
    output="$("$@" 2>&1)" && {
      printf '%s\n' "${output}"
      return 0
    }

    printf '%s\n' "${output}" >&2
    if printf '%s\n' "${output}" | grep -qi "already installed"; then
      echo "Skill '${skill}' already installed; continuing."
      return 0
    fi
    return 1
  }

  if command -v clawhub >/dev/null 2>&1; then
    if run_install_cmd clawhub install "${skill}"; then
      return 0
    fi
  fi

  if command -v npx >/dev/null 2>&1; then
    if run_install_cmd npx -y clawhub@latest install "${skill}"; then
      return 0
    fi
  fi

  return 1
}

if [[ "${#clawhub_skills[@]}" -gt 0 ]]; then
  for skill in "${clawhub_skills[@]}"; do
    echo "Installing ClawHub skill: ${skill}"
    if ! install_skill "${skill}"; then
      echo "Failed to install ClawHub skill: ${skill}" >&2
      exit 1
    fi
  done
else
  echo "No CLAWHUB_SKILLS requested."
fi

if [[ "${#openclaw_skills[@]}" -gt 0 ]]; then
  echo "OpenClaw stock skills (hardcoded + env): ${openclaw_skills[*]}"
  echo "Note: stock OpenClaw skills are managed by OpenClaw itself (no ClawHub install step)."
else
  echo "No OPENCLAW_SKILLS configured."
fi

hook_name_from_hook_md() {
  local hook_md="$1"
  awk '
    BEGIN { in_frontmatter=0; frontmatter_seen=0 }
    /^---[[:space:]]*$/ {
      if (!frontmatter_seen) {
        in_frontmatter=1
        frontmatter_seen=1
        next
      }
      if (in_frontmatter) {
        exit
      }
    }
    in_frontmatter && /^[[:space:]]*name:[[:space:]]*/ {
      line=$0
      sub(/^[[:space:]]*name:[[:space:]]*/, "", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      gsub(/^"|"$/, "", line)
      gsub(/^'\''|'\''$/, "", line)
      print line
      exit
    }
  ' "${hook_md}"
}

if printf '%s\n' "${clawhub_skills[*]-}" | grep -qw "self-improving-agent"; then
  HOOK_SRC_ROOT="/opt/openclaw/skills/self-improving-agent/hooks/openclaw"
  HOOKS_MANAGED_DIR="${HOME}/.openclaw/hooks"
  declare -a installed_hook_dirs=()
  declare -a discovered_hook_names=()

  if [[ -d "${HOOK_SRC_ROOT}" ]]; then
    echo "Installing OpenClaw hook: self-improvement"
    mkdir -p "${HOOKS_MANAGED_DIR}"

    if [[ -f "${HOOK_SRC_ROOT}/HOOK.md" ]]; then
      hook_dir_name="self-improvement"
      hook_dest="${HOOKS_MANAGED_DIR}/${hook_dir_name}"
      mkdir -p "${hook_dest}"
      cp -R "${HOOK_SRC_ROOT}/." "${hook_dest}/"
      installed_hook_dirs+=("${hook_dest}")
    else
      while IFS= read -r -d '' subdir; do
        hook_dir_name="$(basename "${subdir}")"
        hook_dest="${HOOKS_MANAGED_DIR}/${hook_dir_name}"
        mkdir -p "${hook_dest}"
        cp -R "${subdir}/." "${hook_dest}/"
        installed_hook_dirs+=("${hook_dest}")
      done < <(find "${HOOK_SRC_ROOT}" -mindepth 1 -maxdepth 1 -type d -print0)
    fi

    if [[ "${#installed_hook_dirs[@]}" -eq 0 ]]; then
      echo "No hook directories found in ${HOOK_SRC_ROOT}; skipping hook enable."
    else
      for hook_dir in "${installed_hook_dirs[@]}"; do
        hook_md="${hook_dir}/HOOK.md"
        hook_name=""
        if [[ -f "${hook_md}" ]]; then
          hook_name="$(hook_name_from_hook_md "${hook_md}" || true)"
        fi
        if [[ -z "${hook_name}" ]]; then
          hook_name="$(basename "${hook_dir}")"
        fi
        discovered_hook_names+=("${hook_name}")
      done
    fi

    hooks_list_json="$(openclaw hooks list --json 2>/dev/null || true)"
    for hook_name in "${discovered_hook_names[@]}"; do
      if [[ -n "${hooks_list_json}" ]] && ! printf '%s' "${hooks_list_json}" | jq -e --arg name "${hook_name}" '.hooks[]? | select(.name == $name)' >/dev/null 2>&1; then
        echo "Hook '${hook_name}' not discovered yet; skipping enable."
        continue
      fi
      echo "Enabling OpenClaw hook: ${hook_name}"
      hook_enable_output="$(openclaw hooks enable "${hook_name}" 2>&1)" || {
        printf '%s\n' "${hook_enable_output}" >&2
        echo "Hook '${hook_name}' could not be enabled; continuing." >&2
      }
      if [[ -n "${hook_enable_output}" ]]; then
        printf '%s\n' "${hook_enable_output}"
      fi
    done
  else
    echo "Skill hook files not found at ${HOOK_SRC_ROOT}; skipping self-improvement hook setup."
  fi
else
  echo "self-improving-agent not requested; skipping self-improvement hook setup."
fi

echo "Checking installed OpenClaw skills"
openclaw skills check

echo "Installed OpenClaw skills: $(format_skills_with_icons "${openclaw_skills[@]}")"
echo "Installed ClawHub skills: $(format_skills_with_icons "${clawhub_skills[@]}")"
