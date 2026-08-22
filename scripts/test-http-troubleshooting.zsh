#!/bin/zsh

set -euo pipefail
set -o pipefail
umask 077

LAB_SCRIPT_DIR="${0:A:h}"
LAB_REPO_ROOT="${LAB_SCRIPT_DIR:h}"
LAB_ENV_FILE="${LAB_REPO_ROOT}/.env"
LAB_BEFORE_LOG="${LAB_REPO_ROOT}/docs/evidence/logs/06-troubleshooting-before.log"
LAB_AFTER_LOG="${LAB_REPO_ROOT}/docs/evidence/logs/07-troubleshooting-after.log"
LAB_SECRET_DIR="${LAB_REPO_ROOT}/.secrets"

set -a
source "$LAB_ENV_FILE"
set +a

: "${AWS_ACCESS_KEY_ID:?AWS_ACCESS_KEY_ID is required}"
: "${AWS_SECRET_ACCESS_KEY:?AWS_SECRET_ACCESS_KEY is required}"
: "${AWS_SESSION_TOKEN:?AWS_SESSION_TOKEN is required}"
: "${AWS_REGION:?AWS_REGION is required}"
: "${LAB_SECURITY_GROUP_ID:?LAB_SECURITY_GROUP_ID is required}"
: "${LAB_INSTANCE_ID:?LAB_INSTANCE_ID is required}"
: "${LAB_PUBLIC_IP:?LAB_PUBLIC_IP is required}"
: "${LAB_KEY_NAME:?LAB_KEY_NAME is required}"

LAB_PRIVATE_KEY_PATH="${LAB_SECRET_DIR}/${LAB_KEY_NAME}.pem"
if [[ ! -f "$LAB_PRIVATE_KEY_PATH" ]]; then
  printf 'Protected SSH private key is unavailable: %s\n' "$LAB_PRIVATE_KEY_PATH" >&2
  exit 1
fi

mkdir -p "${LAB_BEFORE_LOG:h}"

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

run_logged() {
  local lab_log_file="$1"
  local lab_display="$2"
  shift 2
  run_capture "$lab_log_file" "$lab_display" "$@" >/dev/null
}

log_note() {
  local lab_log_file="$1"
  local lab_note="$2"
  printf '\n[%s] %s\n[exit=0]\n' \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$lab_note" | tee -a "$lab_log_file"
}

LAB_HTTP_RULE_REMOVED=false

restore_http_rule() {
  if [[ "$LAB_HTTP_RULE_REMOVED" == true ]]; then
    set +e
    aws ec2 authorize-security-group-ingress \
      --group-id "$LAB_SECURITY_GROUP_ID" \
      --protocol tcp \
      --port 80 \
      --cidr 0.0.0.0/0 \
      --region "$AWS_REGION" \
      --no-cli-pager >/dev/null 2>&1
    local lab_restore_status=$?
    set -e

    if (( lab_restore_status == 0 )); then
      log_note "$LAB_AFTER_LOG" "emergency restoration: HTTP 80 rule restored by exit trap"
    else
      printf 'WARNING: exit trap could not restore HTTP 80. Restore it immediately.\n' >&2
    fi
  fi
}

trap restore_http_rule EXIT INT TERM

run_logged \
  "$LAB_BEFORE_LOG" \
  "aws ec2 describe-security-groups --group-ids ${LAB_SECURITY_GROUP_ID} <HTTP rule before reproduction>" \
  aws ec2 describe-security-groups \
    --group-ids "$LAB_SECURITY_GROUP_ID" \
    --query 'SecurityGroups[0].IpPermissions[?IpProtocol==`tcp` && FromPort==`80` && ToPort==`80`].IpRanges[].CidrIp' \
    --region "$AWS_REGION" \
    --no-cli-pager

run_logged \
  "$LAB_BEFORE_LOG" \
  "curl --include http://${LAB_PUBLIC_IP}/health <baseline external success>" \
  curl --include --fail --silent --show-error \
    --connect-timeout 5 \
    --max-time 10 \
    "http://${LAB_PUBLIC_IP}/health"

run_logged \
  "$LAB_BEFORE_LOG" \
  "aws ec2 revoke-security-group-ingress --group-id ${LAB_SECURITY_GROUP_ID} --protocol tcp --port 80 --cidr 0.0.0.0/0" \
  aws ec2 revoke-security-group-ingress \
    --group-id "$LAB_SECURITY_GROUP_ID" \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0 \
    --region "$AWS_REGION" \
    --no-cli-pager
LAB_HTTP_RULE_REMOVED=true

run_logged \
  "$LAB_BEFORE_LOG" \
  "aws ec2 describe-security-groups --group-ids ${LAB_SECURITY_GROUP_ID} <HTTP rule absent>" \
  aws ec2 describe-security-groups \
    --group-ids "$LAB_SECURITY_GROUP_ID" \
    --query 'SecurityGroups[0].IpPermissions[?IpProtocol==`tcp` && FromPort==`80` && ToPort==`80`].IpRanges[].CidrIp' \
    --region "$AWS_REGION" \
    --no-cli-pager

set +e
LAB_FAILED_CURL_OUTPUT="$(curl --include --fail --silent --show-error \
  --connect-timeout 5 \
  --max-time 10 \
  "http://${LAB_PUBLIC_IP}/health" 2>&1)"
LAB_FAILED_CURL_STATUS=$?
set -e
{
  printf '\n[%s] $ curl --include http://%s/health <expected external failure>\n' \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$LAB_PUBLIC_IP"
  print -r -- "$LAB_FAILED_CURL_OUTPUT"
  printf '[exit=%d, expected-nonzero=true]\n' "$LAB_FAILED_CURL_STATUS"
} | tee -a "$LAB_BEFORE_LOG"
unset LAB_FAILED_CURL_OUTPUT

if (( LAB_FAILED_CURL_STATUS == 0 )); then
  printf 'External request unexpectedly succeeded after removing HTTP ingress.\n' >&2
  exit 1
fi

run_logged \
  "$LAB_BEFORE_LOG" \
  "ssh -i <protected-key> ec2-user@${LAB_PUBLIC_IP} <localhost health remains 200>" \
  ssh \
    -i "$LAB_PRIVATE_KEY_PATH" \
    -o BatchMode=yes \
    -o ConnectTimeout=10 \
    -o StrictHostKeyChecking=accept-new \
    "ec2-user@${LAB_PUBLIC_IP}" \
    "curl --fail --silent --show-error --write-out 'localhost-status=%{http_code}\\n' --output /dev/null http://127.0.0.1/health && printf 'localhost-body=' && curl --fail --silent --show-error http://127.0.0.1/health"

run_logged \
  "$LAB_AFTER_LOG" \
  "aws ec2 authorize-security-group-ingress --group-id ${LAB_SECURITY_GROUP_ID} --protocol tcp --port 80 --cidr 0.0.0.0/0" \
  aws ec2 authorize-security-group-ingress \
    --group-id "$LAB_SECURITY_GROUP_ID" \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0 \
    --region "$AWS_REGION" \
    --no-cli-pager
LAB_HTTP_RULE_REMOVED=false

run_logged \
  "$LAB_AFTER_LOG" \
  "aws ec2 describe-security-groups --group-ids ${LAB_SECURITY_GROUP_ID} <HTTP rule restored>" \
  aws ec2 describe-security-groups \
    --group-ids "$LAB_SECURITY_GROUP_ID" \
    --query 'SecurityGroups[0].IpPermissions[?IpProtocol==`tcp` && FromPort==`80` && ToPort==`80`].IpRanges[].CidrIp' \
    --region "$AWS_REGION" \
    --no-cli-pager

run_logged \
  "$LAB_AFTER_LOG" \
  "curl --include http://${LAB_PUBLIC_IP}/health <external recovery>" \
  curl --include --fail --silent --show-error \
    --retry 6 \
    --retry-all-errors \
    --retry-delay 2 \
    --connect-timeout 5 \
    --max-time 10 \
    "http://${LAB_PUBLIC_IP}/health"

trap - EXIT INT TERM
printf 'HTTP ingress failure reproduction and recovery completed.\n'
