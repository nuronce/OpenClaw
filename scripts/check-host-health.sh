#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="/var/lib/openclaw-alerts"
NOTIFY_SCRIPT="/opt/openclaw/scripts/notify-slack-clawbot.sh"
MEM_AVAILABLE_THRESHOLD_PCT="${HOST_ALERT_MEM_AVAILABLE_PCT:-10}"
DISK_USED_THRESHOLD_PCT="${HOST_ALERT_DISK_USED_PCT:-85}"

mkdir -p "${STATE_DIR}"

notify() {
  "${NOTIFY_SCRIPT}" "$1"
}

set_state() {
  printf '%s\n' "$2" > "${STATE_DIR}/$1"
}

clear_state() {
  rm -f "${STATE_DIR}/$1"
}

has_state() {
  [[ -f "${STATE_DIR}/$1" ]]
}

HOSTNAME_VALUE="$(hostname)"

MEM_AVAILABLE_PCT="$(
  awk '
    /^MemTotal:/ { total=$2 }
    /^MemAvailable:/ { available=$2 }
    END {
      if (total == 0) {
        print 0
      } else {
        printf "%d", (available * 100) / total
      }
    }
  ' /proc/meminfo
)"

if (( MEM_AVAILABLE_PCT < MEM_AVAILABLE_THRESHOLD_PCT )); then
  if ! has_state mem_low; then
    notify "Clawbot alert: ${HOSTNAME_VALUE} low memory. MemAvailable=${MEM_AVAILABLE_PCT}%."
    set_state mem_low "${MEM_AVAILABLE_PCT}"
  fi
else
  if has_state mem_low; then
    notify "Clawbot recovery: ${HOSTNAME_VALUE} memory recovered. MemAvailable=${MEM_AVAILABLE_PCT}%."
    clear_state mem_low
  fi
fi

for mountpoint in / /srv/openclaw; do
  if mountpoint -q "${mountpoint}" || [[ "${mountpoint}" == "/" ]]; then
    usage="$(
      df -P "${mountpoint}" | awk 'NR==2 {gsub(/%/, "", $5); print $5}'
    )"
    state_key="disk_${mountpoint//[^A-Za-z0-9]/_}"
    if (( usage >= DISK_USED_THRESHOLD_PCT )); then
      if ! has_state "${state_key}"; then
        notify "Clawbot alert: ${HOSTNAME_VALUE} disk usage high on ${mountpoint}. Used=${usage}%."
        set_state "${state_key}" "${usage}"
      fi
    else
      if has_state "${state_key}"; then
        notify "Clawbot recovery: ${HOSTNAME_VALUE} disk usage recovered on ${mountpoint}. Used=${usage}%."
        clear_state "${state_key}"
      fi
    fi
  fi
done
