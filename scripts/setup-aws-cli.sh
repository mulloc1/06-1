#!/usr/bin/env bash

set -euo pipefail
umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"
ENV_EXAMPLE="$ROOT_DIR/.env.example"
LOG_DIR="$ROOT_DIR/docs/evidence/logs"
CLI_LOG="$LOG_DIR/00-cli-version.log"
IAM_LOG="$LOG_DIR/01-iam-validation.log"

# 실행 전에 필요한 로컬 프로그램이 설치되어 있는지 확인한다.
need() {
  command -v "$1" >/dev/null 2>&1 || {
    printf '필수 프로그램을 찾을 수 없습니다: %s\n' "$1" >&2
    exit 1
  }
}

# .env의 기존 키는 교체하고, 없는 키는 마지막에 추가한다.
set_env() {
  local key="$1" value="$2" tmp
  tmp="$(mktemp "$ROOT_DIR/.env.tmp.XXXXXX")"
  LAB_KEY="$key" LAB_VALUE="$value" awk '
    BEGIN { key=ENVIRON["LAB_KEY"]; value=ENVIRON["LAB_VALUE"]; found=0 }
    index($0, key "=")==1 { print key "=" value; found=1; next }
    { print }
    END { if (!found) print key "=" value }
  ' "$ENV_FILE" > "$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$ENV_FILE"
}

# 비어 있는 필수 값만 입력받으며 Secret Key는 화면에 표시하지 않는다.
prompt_value() {
  local name="$1" message="$2" secret="${3:-false}" value="${!name:-}"
  [[ -n "$value" ]] && return
  if [[ "$secret" == true ]]; then
    read -r -s -p "$message" value
    printf '\n'
  else
    read -r -p "$message" value
  fi
  [[ -n "$value" ]] || { printf '%s 값은 비워둘 수 없습니다.\n' "$name" >&2; exit 1; }
  set_env "$name" "$value"
  printf -v "$name" '%s' "$value"
  export "$name"
  unset value
}

# 민감 값을 제외한 명령·출력·종료 코드를 증거 로그에 기록한다.
log_capture() {
  local file="$1" description="$2" display="$3" output status
  shift 3
  set +e
  output="$("$@" 2>&1)"
  status=$?
  set -e
  {
    printf '\n# 설명: %s\n' "$description"
    printf '[%s] $ %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$display"
    printf '%s\n[exit=%d]\n' "$output" "$status"
  } | tee -a "$file" >&2
  (( status == 0 )) || return "$status"
  printf '%s\n' "$output"
}

need aws
need awk
need mktemp
need tee
(( $# == 0 )) || { printf '사용법: ./scripts/setup-aws-cli.sh\n' >&2; exit 2; }

# 최초 실행이면 템플릿으로 로컬 환경 파일을 만들고 접근 권한을 제한한다.
if [[ ! -f "$ENV_FILE" ]]; then
  [[ -f "$ENV_EXAMPLE" ]] || { printf '.env.example을 찾을 수 없습니다.\n' >&2; exit 1; }
  cp "$ENV_EXAMPLE" "$ENV_FILE"
fi
chmod 600 "$ENV_FILE"

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

AWS_REGION="${AWS_REGION:-ap-northeast-2}"
AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-$AWS_REGION}"
AWS_DEFAULT_OUTPUT="${AWS_DEFAULT_OUTPUT:-json}"
set_env AWS_REGION "$AWS_REGION"
set_env AWS_DEFAULT_REGION "$AWS_DEFAULT_REGION"
set_env AWS_DEFAULT_OUTPUT "$AWS_DEFAULT_OUTPUT"

# 장기 IAM 자격 증명과 MFA 장치 정보는 로컬 .env에만 보관한다.
prompt_value AWS_BASE_ACCESS_KEY_ID 'IAM 사용자의 Access Key ID: '
prompt_value AWS_BASE_SECRET_ACCESS_KEY 'IAM 사용자의 Secret Access Key: ' true
prompt_value AWS_MFA_SERIAL 'IAM MFA 장치 ARN: '

read -r -s -p 'MFA 6자리 코드: ' MFA_CODE
printf '\n'
[[ "$MFA_CODE" =~ ^[0-9]{6}$ ]] || { unset MFA_CODE; printf 'MFA 코드는 숫자 6자리여야 합니다.\n' >&2; exit 1; }

# 장기 키와 MFA 코드로 12시간짜리 임시 세션을 발급한다. 이 호출은 로그에 남기지 않는다.
SESSION_OUTPUT="$(
  AWS_ACCESS_KEY_ID="$AWS_BASE_ACCESS_KEY_ID" \
  AWS_SECRET_ACCESS_KEY="$AWS_BASE_SECRET_ACCESS_KEY" \
  AWS_SESSION_TOKEN= \
  aws sts get-session-token \
    --serial-number "$AWS_MFA_SERIAL" \
    --token-code "$MFA_CODE" \
    --duration-seconds 43200 \
    --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken,Expiration]' \
    --output text --region "$AWS_REGION" --no-cli-pager
)"
unset MFA_CODE

IFS=$'\t' read -r NEW_ACCESS_KEY NEW_SECRET_KEY NEW_SESSION_TOKEN SESSION_EXPIRATION <<< "$SESSION_OUTPUT"
unset SESSION_OUTPUT
: "${NEW_ACCESS_KEY:?임시 Access Key가 반환되지 않았습니다}"
: "${NEW_SECRET_KEY:?임시 Secret Key가 반환되지 않았습니다}"
: "${NEW_SESSION_TOKEN:?임시 Session Token이 반환되지 않았습니다}"

set_env AWS_ACCESS_KEY_ID "$NEW_ACCESS_KEY"
set_env AWS_SECRET_ACCESS_KEY "$NEW_SECRET_KEY"
set_env AWS_SESSION_TOKEN "$NEW_SESSION_TOKEN"
export AWS_ACCESS_KEY_ID="$NEW_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$NEW_SECRET_KEY"
export AWS_SESSION_TOKEN="$NEW_SESSION_TOKEN"
unset NEW_ACCESS_KEY NEW_SECRET_KEY NEW_SESSION_TOKEN

# 새 임시 세션으로 CLI 동작과 IAM 최소 권한을 안전한 형태로 검증한다.
mkdir -p "$LOG_DIR"
: > "$CLI_LOG"
: > "$IAM_LOG"
chmod 600 "$CLI_LOG" "$IAM_LOG"

log_capture "$CLI_LOG" '설치된 AWS CLI의 버전과 실행 환경을 확인한다.' 'aws --version' aws --version >/dev/null
CALLER_MATCH="$(log_capture "$IAM_LOG" \
  '현재 MFA 세션의 호출자가 실습용 IAM 사용자인지 Boolean 값으로 확인한다.' \
  "aws sts get-caller-identity --query contains(Arn, 'user/lab-cloud-web') <boolean only>" \
  aws sts get-caller-identity --query "contains(Arn, 'user/lab-cloud-web')" \
    --output text --region "$AWS_REGION" --no-cli-pager)"
case "$CALLER_MATCH" in True|true) ;; *) printf '현재 호출자가 lab-cloud-web 사용자가 아닙니다.\n' >&2; exit 1 ;; esac

log_capture "$IAM_LOG" 'EC2 조회 권한이 허용되는지 VPC 개수만 조회해 확인한다.' \
  'aws ec2 describe-vpcs <EC2 read permission; count only>' \
  aws ec2 describe-vpcs --query 'length(Vpcs)' --output text \
    --region "$AWS_REGION" --no-cli-pager >/dev/null

set +e
aws s3api list-buckets --query 'length(Buckets)' --output text \
  --region "$AWS_REGION" --no-cli-pager >/dev/null 2>&1
S3_STATUS=$?
aws iam list-users --query 'length(Users)' --output text \
  --region "$AWS_REGION" --no-cli-pager >/dev/null 2>&1
IAM_STATUS=$?
set -e

{
  printf '\n# 설명: 실습과 무관한 S3 및 IAM 조회가 최소 권한 정책에 의해 거부되는지 확인한다.\n'
  printf '[%s] unrelated_permission_checks\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  (( S3_STATUS != 0 )) && printf 's3_access=DENIED_AS_EXPECTED\n' || printf 's3_access=ALLOWED_UNEXPECTEDLY\n'
  (( IAM_STATUS != 0 )) && printf 'iam_list_users=DENIED_AS_EXPECTED\n' || printf 'iam_list_users=ALLOWED_UNEXPECTEDLY\n'
} | tee -a "$IAM_LOG"
(( S3_STATUS != 0 && IAM_STATUS != 0 )) || { printf '최소 권한 정책을 다시 확인하세요.\n' >&2; exit 1; }

printf 'AWS CLI 연동 완료\n'
printf '  호출자: lab-cloud-web\n  리전: %s\n  MFA 세션 만료: %s\n' "$AWS_REGION" "$SESSION_EXPIRATION"
