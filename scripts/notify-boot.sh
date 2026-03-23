#!/usr/bin/env bash
set -euo pipefail

NOTIFY_SCRIPT="/opt/openclaw/scripts/notify-slack-clawbot.sh"
MEM_AVAILABLE_THRESHOLD_PCT="${HOST_ALERT_MEM_AVAILABLE_PCT:-10}"
DISK_USED_THRESHOLD_PCT="${HOST_ALERT_DISK_USED_PCT:-85}"
HOSTNAME_VALUE="$(hostname)"

# ---------- gather resource snapshot ----------

WARNINGS=()

# Memory
MEM_AVAILABLE_PCT="$(
  awk '
    /^MemTotal:/ { total=$2 }
    /^MemAvailable:/ { available=$2 }
    END {
      if (total == 0) { print 0 }
      else { printf "%d", (available * 100) / total }
    }
  ' /proc/meminfo
)"
MEM_TOTAL_MB="$(awk '/^MemTotal:/ { printf "%d", $2/1024 }' /proc/meminfo)"
MEM_AVAIL_MB="$(awk '/^MemAvailable:/ { printf "%d", $2/1024 }' /proc/meminfo)"

if (( MEM_AVAILABLE_PCT < MEM_AVAILABLE_THRESHOLD_PCT )); then
  WARNINGS+=("Memory low: ${MEM_AVAIL_MB}MB available of ${MEM_TOTAL_MB}MB (${MEM_AVAILABLE_PCT}% free, threshold ${MEM_AVAILABLE_THRESHOLD_PCT}%)")
fi

# Disk
for mountpoint in / /srv/openclaw; do
  if mountpoint -q "${mountpoint}" 2>/dev/null || [[ "${mountpoint}" == "/" ]]; then
    usage="$(df -P "${mountpoint}" | awk 'NR==2 {gsub(/%/, "", $5); print $5}')"
    if (( usage >= DISK_USED_THRESHOLD_PCT )); then
      WARNINGS+=("Disk usage high on ${mountpoint}: ${usage}% used (threshold ${DISK_USED_THRESHOLD_PCT}%)")
    fi
  fi
done

# ---------- build message ----------

MSG="Clawbot notice: ${HOSTNAME_VALUE} booted at $(date -Is)."

if (( ${#WARNINGS[@]} > 0 )); then
  MSG+=$'\n\nResource constraints detected:'
  for w in "${WARNINGS[@]}"; do
    MSG+=$'\n  - '"${w}"
  done
else
  MSG+=$'\nAll resource checks passed (mem '${MEM_AVAILABLE_PCT}'% free, disk OK).'
fi

"${NOTIFY_SCRIPT}" "${MSG}"
