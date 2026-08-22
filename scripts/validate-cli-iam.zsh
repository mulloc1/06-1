#!/bin/zsh

set -euo pipefail
set -o pipefail
umask 077

LAB_SCRIPT_DIR="${0:A:h}"
LAB_REPO_ROOT="${LAB_SCRIPT_DIR:h}"
LAB_ENV_FILE="${LAB_REPO_ROOT}/.env"
LAB_CLI_LOG="${LAB_REPO_ROOT}/docs/evidence/logs/00-cli-version.log"
LAB_IAM_LOG="${LAB_REPO_ROOT}/docs/evidence/logs/01-iam-validation.log"

set -a
source "$LAB_ENV_FILE"
set +a

: "${AWS_ACCESS_KEY_ID:?AWS_ACCESS_KEY_ID is required}"
: "${AWS_SECRET_ACCESS_KEY:?AWS_SECRET_ACCESS_KEY is required}"
: "${AWS_SESSION_TOKEN:?AWS_SESSION_TOKEN is required}"
: "${AWS_REGION:?AWS_REGION is required}"

mkdir -p "${LAB_CLI_LOG:h}"

run_capture() {
  local lab_log_file="$1"
  local lab_display="$2"
  shift 2
  local lab_output
  local lab_status

  set +e
  lab_output="$("$@" 2>&1)"
  lab_status=$?
  set -e

  {
    printf '\n[%s] $ %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$lab_display"
    print -r -- "$lab_output"
    printf '[exit=%d]\n' "$lab_status"
  } | tee -a "$lab_log_file" >&2

  if (( lab_status != 0 )); then
    return "$lab_status"
  fi

  print -r -- "$lab_output"
}

run_capture "$LAB_CLI_LOG" "aws --version" aws --version >/dev/null

run_capture \
  "$LAB_IAM_LOG" \
  "aws sts get-caller-identity --query contains(Arn, 'user/lab-cloud-web') <boolean only>" \
  aws sts get-caller-identity \
    --query "contains(Arn, 'user/lab-cloud-web')" \
    --output text \
    --region "$AWS_REGION" \
    --no-cli-pager >/dev/null

run_capture \
  "$LAB_IAM_LOG" \
  "aws ec2 describe-vpcs <EC2 read permission check, count only>" \
  aws ec2 describe-vpcs \
    --query 'length(Vpcs)' \
    --output text \
    --region "$AWS_REGION" \
    --no-cli-pager >/dev/null

set +e
aws s3api list-buckets \
  --query 'length(Buckets)' \
  --output text \
  --region "$AWS_REGION" \
  --no-cli-pager >/dev/null 2>&1
LAB_S3_STATUS=$?

aws iam list-users \
  --query 'length(Users)' \
  --output text \
  --region "$AWS_REGION" \
  --no-cli-pager >/dev/null 2>&1
LAB_IAM_STATUS=$?
set -e

{
  printf '\n[%s] $ aws s3api list-buckets <unrelated service permission check; output suppressed>\n' \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  if (( LAB_S3_STATUS == 0 )); then
    printf 's3_access=ALLOWED_UNEXPECTEDLY\n'
  else
    printf 's3_access=DENIED_AS_EXPECTED\n'
  fi
  printf '[exit=%d, expected-nonzero=true]\n' "$LAB_S3_STATUS"

  printf '\n[%s] $ aws iam list-users <IAM administration permission check; output suppressed>\n' \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  if (( LAB_IAM_STATUS == 0 )); then
    printf 'iam_list_users=ALLOWED_UNEXPECTEDLY\n'
  else
    printf 'iam_list_users=DENIED_AS_EXPECTED\n'
  fi
  printf '[exit=%d, expected-nonzero=true]\n' "$LAB_IAM_STATUS"
} | tee -a "$LAB_IAM_LOG"

if (( LAB_S3_STATUS == 0 || LAB_IAM_STATUS == 0 )); then
  printf 'Unexpected unrelated-service permission detected.\n' >&2
  exit 1
fi

printf 'AWS CLI and IAM least-privilege validation completed.\n'
