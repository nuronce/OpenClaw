#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="/opt/openclaw/deploy/.env"

get_env_value() {
  local key="$1"
  awk -F= -v search="${key}" '$1 == search {print substr($0, index($0, "=") + 1); exit}' "${ENV_FILE}"
}

KEY_PAIR_NAME="$(get_env_value KEY_PAIR_NAME)"

if [[ -z "${KEY_PAIR_NAME}" ]]; then
  echo "KEY_PAIR_NAME not set in ${ENV_FILE}; skipping SSH key install."
  exit 0
fi

REGION="$(get_env_value AWS_REGION)"
if [[ -z "${REGION}" ]]; then
  REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
fi

AWS_REGION_ARGS=()
if [[ -n "${REGION}" ]]; then
  AWS_REGION_ARGS+=(--region "${REGION}")
fi

PUBLIC_KEY="$(aws ec2 describe-key-pairs \
  --key-names "${KEY_PAIR_NAME}" \
  --include-public-key \
  "${AWS_REGION_ARGS[@]}" \
  --query "KeyPairs[0].PublicKey" \
  --output text 2>/dev/null || true)"

if [[ -z "${PUBLIC_KEY}" || "${PUBLIC_KEY}" == "None" ]]; then
  if [[ -z "${REGION}" ]]; then
    echo "Could not retrieve public key for EC2 key pair '${KEY_PAIR_NAME}'. Set AWS_REGION in ${ENV_FILE}, export AWS_REGION/AWS_DEFAULT_REGION, or configure a default AWS CLI region." >&2
  else
    echo "Could not retrieve public key for EC2 key pair '${KEY_PAIR_NAME}' in region '${REGION}'." >&2
  fi
  exit 1
fi

SSH_DIR="/home/ec2-user/.ssh"
AUTH_KEYS="${SSH_DIR}/authorized_keys"

install -d -m 700 -o ec2-user -g ec2-user "${SSH_DIR}"

if ! grep -qF "${PUBLIC_KEY}" "${AUTH_KEYS}" 2>/dev/null; then
  printf '%s\n' "${PUBLIC_KEY}" >> "${AUTH_KEYS}"
  echo "Installed public key from EC2 key pair '${KEY_PAIR_NAME}'."
else
  echo "Public key from EC2 key pair '${KEY_PAIR_NAME}' already present."
fi

chmod 600 "${AUTH_KEYS}"
chown ec2-user:ec2-user "${AUTH_KEYS}"
