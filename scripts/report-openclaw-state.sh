#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -eq 0 ]]; then
  echo "Run this script as a non-root user such as ec2-user." >&2
  exit 1
fi

version_output="$(openclaw --version 2>/dev/null | head -n1 || true)"
if [[ -z "${version_output}" ]]; then
  version_output="$(openclaw version 2>/dev/null | head -n1 || true)"
fi
if [[ -z "${version_output}" ]]; then
  version_output="unknown"
fi

echo "OpenClaw version: ${version_output}"

join_lines() {
  awk 'NF { if (!first) printf ", "; printf "%s", $0; first=0 } END { if (!first) printf "\n" }'
}

server_names="$(
  while IFS= read -r -d '' server_path; do
    basename "${server_path}"
  done < <(find "${HOME}/.openclaw/mcp/servers.d" -maxdepth 1 -type f -name '*.json' -print0 2>/dev/null) \
    | sed -E 's/\.sample\.json$//; s/\.json$//' \
    | awk 'NF && !seen[$0]++'
)"

if [[ -z "${server_names}" ]]; then
  mcp_file=""
  for candidate in "${HOME}/.openclaw/mcpservers.json" "${HOME}/.openclaw/mcp/mcpservers.json"; do
    if [[ -f "${candidate}" ]]; then
      mcp_file="${candidate}"
      break
    fi
  done
  if [[ -n "${mcp_file}" ]]; then
    server_names="$(jq -r '.mcpServers // {} | keys[]?' "${mcp_file}" 2>/dev/null || true)"
  fi
fi

if [[ -n "${server_names}" ]]; then
  echo "Configured MCP servers: $(printf '%s\n' "${server_names}" | join_lines)"
else
  echo "Configured MCP servers: none"
fi
