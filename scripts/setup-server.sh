#!/usr/bin/env bash

set -euo pipefail
umask 077

LAB_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LAB_REPO_ROOT="$(cd -- "${LAB_SCRIPT_DIR}/.." && pwd)"
LAB_ENV_FILE="${LAB_REPO_ROOT}/.env"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf '필수 프로그램을 찾을 수 없습니다: %s\n' "$1" >&2
    exit 1
  fi
}

require_command aws
require_command curl
require_command jq
require_command ssh
require_command zsh

if [[ ! -f "$LAB_ENV_FILE" ]]; then
  printf '.env가 없습니다. 먼저 다음 명령을 실행하세요.\n' >&2
  printf '  ./scripts/setup-aws-cli.sh\n' >&2
  exit 1
fi
chmod 600 "$LAB_ENV_FILE"

set -a
# shellcheck disable=SC1090
source "$LAB_ENV_FILE"
set +a

: "${AWS_ACCESS_KEY_ID:?AWS CLI MFA 세션이 없습니다. setup-aws-cli.sh를 먼저 실행하세요}"
: "${AWS_SECRET_ACCESS_KEY:?AWS CLI MFA 세션이 없습니다. setup-aws-cli.sh를 먼저 실행하세요}"
: "${AWS_SESSION_TOKEN:?AWS CLI MFA 세션이 없습니다. setup-aws-cli.sh를 먼저 실행하세요}"
: "${AWS_REGION:?AWS_REGION이 필요합니다}"

if [[ "$AWS_REGION" != "ap-northeast-2" ]]; then
  printf '이 과제는 서울 리전(ap-northeast-2) 전용입니다. 현재 값: %s\n' "$AWS_REGION" >&2
  exit 1
fi

if ! aws sts get-caller-identity \
  --query "contains(Arn, 'user/lab-cloud-web')" \
  --output text \
  --region "$AWS_REGION" \
  --no-cli-pager | grep -Eiq '^true$'; then
  printf 'AWS 세션이 만료됐거나 lab-cloud-web 사용자가 아닙니다.\n' >&2
  printf '먼저 ./scripts/setup-aws-cli.sh를 다시 실행하세요.\n' >&2
  exit 1
fi

printf '[1/2] VPC, Public Subnet, Internet Gateway, Route Table 구성\n'
zsh "${LAB_SCRIPT_DIR}/provision-network.zsh"

printf '[2/2] Security Group, Key Pair, EC2, Nginx 구성 및 접속 검증\n'
zsh "${LAB_SCRIPT_DIR}/provision-compute.zsh"

set -a
# provision scripts populate IDs and the public IP in .env.
# shellcheck disable=SC1090
source "$LAB_ENV_FILE"
set +a

: "${LAB_PUBLIC_IP:?서버의 Public IPv4를 확인하지 못했습니다}"

printf '\n서버 설정 완료\n'
printf '  웹 페이지: http://%s/\n' "$LAB_PUBLIC_IP"
printf '  상태 확인: http://%s/health\n' "$LAB_PUBLIC_IP"
printf '  원본 로그: %s\n' "${LAB_REPO_ROOT}/docs/evidence/logs"
printf '  SSH 접속 로그: %s\n' "${LAB_REPO_ROOT}/docs/evidence/logs/04-ssh-connection.log"
printf '  HTTP 200 로그: %s\n' "${LAB_REPO_ROOT}/docs/evidence/logs/05-http-200-ok.log"
printf '\n화면 캡처와 장애 재현은 이 자동 설정에 포함되지 않습니다.\n'
