#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="/opt/openclaw/deploy/.env"
ARCHIVE_ROOT="/var/log/openclaw/archive"
OPENCLAW_LOG_ROOT="/tmp/openclaw"

if [[ -f "${ENV_FILE}" ]]; then
  get_env_value() {
    local key="$1"
    awk -F= -v search="${key}" '$1 == search {print substr($0, index($0, "=") + 1); exit}' "${ENV_FILE}"
  }

  S3_ARCHIVE_BUCKET="${S3_ARCHIVE_BUCKET:-$(get_env_value S3_ARCHIVE_BUCKET)}"
  S3_ARCHIVE_PREFIX="${S3_ARCHIVE_PREFIX:-$(get_env_value S3_ARCHIVE_PREFIX)}"
  LOCAL_ARCHIVE_RETENTION_DAYS="${LOCAL_ARCHIVE_RETENTION_DAYS:-$(get_env_value LOCAL_ARCHIVE_RETENTION_DAYS)}"
fi

: "${S3_ARCHIVE_BUCKET:?S3_ARCHIVE_BUCKET must be set}"
: "${S3_ARCHIVE_PREFIX:?S3_ARCHIVE_PREFIX must be set}"

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
day_path="$(date -u +%Y/%m/%d)"
archive_file="${ARCHIVE_ROOT}/openclaw-${timestamp}.log"
gzip_file="${archive_file}.gz"

mkdir -p "${ARCHIVE_ROOT}"

{
  echo "===== openclaw host logs ====="
  if compgen -G "${OPENCLAW_LOG_ROOT}/openclaw-*.log" > /dev/null; then
    find "${OPENCLAW_LOG_ROOT}" -maxdepth 1 -type f -name 'openclaw-*.log' -mtime -2 -print0 | xargs -0 cat
  else
    echo "No OpenClaw host logs found under ${OPENCLAW_LOG_ROOT}"
  fi
} > "${archive_file}"

gzip -f "${archive_file}"

aws s3 cp "${gzip_file}" "s3://${S3_ARCHIVE_BUCKET}/${S3_ARCHIVE_PREFIX}/logs/${day_path}/$(basename "${gzip_file}")"

find "${ARCHIVE_ROOT}" -type f -mtime +"${LOCAL_ARCHIVE_RETENTION_DAYS:-7}" -delete
