#!/usr/bin/env bash

set -euo pipefail
umask 077

LAB_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LAB_REPO_ROOT="$(cd -- "${LAB_SCRIPT_DIR}/.." && pwd)"
LAB_ENV_FILE="${LAB_REPO_ROOT}/.env"
LAB_ENV_EXAMPLE="${LAB_REPO_ROOT}/.env.example"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf '필수 프로그램을 찾을 수 없습니다: %s\n' "$1" >&2
    exit 1
  fi
}

persist_env_value() {
  local lab_key="$1"
  local lab_value="$2"
  local lab_tmp_file

  lab_tmp_file="$(mktemp "${LAB_REPO_ROOT}/.env.tmp.XXXXXX")"
  LAB_PERSIST_KEY="$lab_key" LAB_PERSIST_VALUE="$lab_value" \
    awk '
      BEGIN {
        key = ENVIRON["LAB_PERSIST_KEY"]
        value = ENVIRON["LAB_PERSIST_VALUE"]
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
}

prompt_required_value() {
  local lab_variable_name="$1"
  local lab_prompt="$2"
  local lab_secret="${3:-false}"
  local lab_current_value="${!lab_variable_name:-}"
  local lab_entered_value

  if [[ -n "$lab_current_value" ]]; then
    return 0
  fi

  if [[ "$lab_secret" == "true" ]]; then
    read -r -s -p "$lab_prompt" lab_entered_value
    printf '\n'
  else
    read -r -p "$lab_prompt" lab_entered_value
  fi

  if [[ -z "$lab_entered_value" ]]; then
    printf '%s 값은 비워둘 수 없습니다.\n' "$lab_variable_name" >&2
    exit 1
  fi

  persist_env_value "$lab_variable_name" "$lab_entered_value"
  printf -v "$lab_variable_name" '%s' "$lab_entered_value"
  export "$lab_variable_name"
  unset lab_entered_value
}

require_command aws
require_command awk
require_command mktemp

if [[ ! -f "$LAB_ENV_FILE" ]]; then
  if [[ ! -f "$LAB_ENV_EXAMPLE" ]]; then
    printf '.env.example을 찾을 수 없습니다: %s\n' "$LAB_ENV_EXAMPLE" >&2
    exit 1
  fi

  cp "$LAB_ENV_EXAMPLE" "$LAB_ENV_FILE"
fi
chmod 600 "$LAB_ENV_FILE"

set -a
# shellcheck disable=SC1090
source "$LAB_ENV_FILE"
set +a

AWS_REGION="${AWS_REGION:-ap-northeast-2}"
AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-$AWS_REGION}"
AWS_DEFAULT_OUTPUT="${AWS_DEFAULT_OUTPUT:-json}"

persist_env_value AWS_REGION "$AWS_REGION"
persist_env_value AWS_DEFAULT_REGION "$AWS_DEFAULT_REGION"
persist_env_value AWS_DEFAULT_OUTPUT "$AWS_DEFAULT_OUTPUT"

prompt_required_value \
  AWS_BASE_ACCESS_KEY_ID \
  'IAM 사용자의 Access Key ID: '

prompt_required_value \
  AWS_BASE_SECRET_ACCESS_KEY \
  'IAM 사용자의 Secret Access Key: ' \
  true

prompt_required_value \
  AWS_MFA_SERIAL \
  'IAM MFA 장치 ARN: '

read -r -s -p 'MFA 6자리 코드: ' LAB_MFA_CODE
printf '\n'

if ! [[ "$LAB_MFA_CODE" =~ ^[0-9]{6}$ ]]; then
  unset LAB_MFA_CODE
  printf 'MFA 코드는 숫자 6자리여야 합니다.\n' >&2
  exit 1
fi

LAB_SESSION_OUTPUT="$(
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

IFS=$'\t' read -r \
  LAB_NEW_ACCESS_KEY \
  LAB_NEW_SECRET_KEY \
  LAB_NEW_SESSION_TOKEN \
  LAB_SESSION_EXPIRATION <<< "$LAB_SESSION_OUTPUT"
unset LAB_SESSION_OUTPUT

: "${LAB_NEW_ACCESS_KEY:?임시 Access Key가 반환되지 않았습니다}"
: "${LAB_NEW_SECRET_KEY:?임시 Secret Key가 반환되지 않았습니다}"
: "${LAB_NEW_SESSION_TOKEN:?임시 Session Token이 반환되지 않았습니다}"

persist_env_value AWS_ACCESS_KEY_ID "$LAB_NEW_ACCESS_KEY"
persist_env_value AWS_SECRET_ACCESS_KEY "$LAB_NEW_SECRET_KEY"
persist_env_value AWS_SESSION_TOKEN "$LAB_NEW_SESSION_TOKEN"
chmod 600 "$LAB_ENV_FILE"

export AWS_ACCESS_KEY_ID="$LAB_NEW_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$LAB_NEW_SECRET_KEY"
export AWS_SESSION_TOKEN="$LAB_NEW_SESSION_TOKEN"
unset LAB_NEW_ACCESS_KEY LAB_NEW_SECRET_KEY LAB_NEW_SESSION_TOKEN

LAB_CALLER_MATCH="$(
  aws sts get-caller-identity \
    --query "contains(Arn, 'user/lab-cloud-web')" \
    --output text \
    --region "$AWS_REGION" \
    --no-cli-pager
)"

if [[ "$LAB_CALLER_MATCH" != "True" && "$LAB_CALLER_MATCH" != "true" ]]; then
  printf '경고: 현재 호출자가 lab-cloud-web IAM 사용자와 일치하지 않습니다.\n' >&2
  exit 1
fi

printf 'AWS CLI 연동 완료\n'
printf '  호출자: lab-cloud-web 확인\n'
printf '  리전: %s\n' "$AWS_REGION"
printf '  MFA 세션 만료: %s\n' "$LAB_SESSION_EXPIRATION"
printf '  환경 파일: %s (권한 600)\n' "$LAB_ENV_FILE"

