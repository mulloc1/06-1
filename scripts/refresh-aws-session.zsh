#!/bin/zsh

set -euo pipefail
umask 077

LAB_SCRIPT_DIR="${0:A:h}"
LAB_REPO_ROOT="${LAB_SCRIPT_DIR:h}"
LAB_ENV_FILE="${LAB_REPO_ROOT}/.env"

if [[ ! -f "$LAB_ENV_FILE" ]]; then
  printf '.env not found: %s\n' "$LAB_ENV_FILE" >&2
  exit 1
fi

set -a
source "$LAB_ENV_FILE"
set +a

: "${AWS_BASE_ACCESS_KEY_ID:?AWS_BASE_ACCESS_KEY_ID is required}"
: "${AWS_BASE_SECRET_ACCESS_KEY:?AWS_BASE_SECRET_ACCESS_KEY is required}"
: "${AWS_MFA_SERIAL:?AWS_MFA_SERIAL is required}"
: "${AWS_REGION:?AWS_REGION is required}"

persist_session_value() {
  local lab_key="$1"
  local lab_value="$2"
  local lab_tmp_file

  lab_tmp_file="$(mktemp "${LAB_REPO_ROOT}/.env.tmp.XXXXXX")"
  export LAB_SESSION_ENV_KEY="$lab_key"
  export LAB_SESSION_ENV_VALUE="$lab_value"

  awk '
    BEGIN {
      key = ENVIRON["LAB_SESSION_ENV_KEY"]
      value = ENVIRON["LAB_SESSION_ENV_VALUE"]
      found = 0
    }
    index($0, key "=") == 1 {
      print key "=" value
      found = 1
      next
    }
    { print }
    END {
      if (!found) print key "=" value
    }
  ' "$LAB_ENV_FILE" > "$lab_tmp_file"

  chmod 600 "$lab_tmp_file"
  mv "$lab_tmp_file" "$LAB_ENV_FILE"
  unset LAB_SESSION_ENV_KEY LAB_SESSION_ENV_VALUE
}

read -s "LAB_MFA_CODE?MFA code: "
printf '\n'

read -r LAB_NEW_ACCESS_KEY LAB_NEW_SECRET_KEY LAB_NEW_SESSION_TOKEN LAB_SESSION_EXPIRATION <<< "$(
  AWS_ACCESS_KEY_ID="$AWS_BASE_ACCESS_KEY_ID" \
  AWS_SECRET_ACCESS_KEY="$AWS_BASE_SECRET_ACCESS_KEY" \
  AWS_SESSION_TOKEN= \
  aws sts get-session-token \
    --serial-number "$AWS_MFA_SERIAL" \
    --token-code "$LAB_MFA_CODE" \
    --duration-seconds 43200 \
    --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken,Expiration]' \
    --output text \
    --region "$AWS_REGION" \
    --no-cli-pager
)"

unset LAB_MFA_CODE

: "${LAB_NEW_ACCESS_KEY:?temporary access key was not returned}"
: "${LAB_NEW_SECRET_KEY:?temporary secret key was not returned}"
: "${LAB_NEW_SESSION_TOKEN:?session token was not returned}"

persist_session_value AWS_ACCESS_KEY_ID "$LAB_NEW_ACCESS_KEY"
persist_session_value AWS_SECRET_ACCESS_KEY "$LAB_NEW_SECRET_KEY"
persist_session_value AWS_SESSION_TOKEN "$LAB_NEW_SESSION_TOKEN"
chmod 600 "$LAB_ENV_FILE"

unset LAB_NEW_ACCESS_KEY LAB_NEW_SECRET_KEY LAB_NEW_SESSION_TOKEN

printf 'Temporary MFA session saved to .env.\n'
printf 'Expires at: %s\n' "$LAB_SESSION_EXPIRATION"
