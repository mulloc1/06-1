#!/usr/bin/env bash

set -euo pipefail
set -o pipefail
umask 077

LAB_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LAB_REPO_ROOT="$(cd -- "${LAB_SCRIPT_DIR}/.." && pwd)"
LAB_ENV_FILE="${LAB_REPO_ROOT}/.env"
LAB_LOG_FILE="${LAB_REPO_ROOT}/docs/evidence/logs/02-network-validation.log"

usage() {
  cat <<'EOF'
사용법:
  ./scripts/verify-network.sh

읽기 전용으로 다음 항목을 조회하고 PASS/FAIL을 기록합니다.
  VPC, Public Subnet, Internet Gateway, Route Table,
  local 경로, 0.0.0.0/0 → IGW 경로, Subnet 연결

결과 로그:
  docs/evidence/logs/02-network-validation.log
EOF
}

case "${1:-}" in
  "") ;;
  --help|-h)
    usage
    exit 0
    ;;
  *)
    printf '알 수 없는 옵션: %s\n\n' "$1" >&2
    usage >&2
    exit 2
    ;;
esac

if (( $# > 1 )); then
  printf '옵션은 하나만 지정할 수 있습니다.\n' >&2
  exit 2
fi

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf '필수 프로그램을 찾을 수 없습니다: %s\n' "$1" >&2
    exit 1
  fi
}

require_command aws
require_command date
require_command grep
require_command tee
require_command tr

if [[ ! -f "$LAB_ENV_FILE" ]]; then
  printf '.env를 찾을 수 없습니다: %s\n' "$LAB_ENV_FILE" >&2
  exit 1
fi
chmod 600 "$LAB_ENV_FILE"

set -a
# shellcheck disable=SC1090
source "$LAB_ENV_FILE"
set +a

: "${AWS_ACCESS_KEY_ID:?AWS CLI MFA 세션이 필요합니다}"
: "${AWS_SECRET_ACCESS_KEY:?AWS CLI MFA 세션이 필요합니다}"
: "${AWS_SESSION_TOKEN:?AWS CLI MFA 세션이 필요합니다}"
: "${AWS_REGION:?AWS_REGION이 필요합니다}"
: "${LAB_PROJECT:?LAB_PROJECT가 필요합니다}"
: "${LAB_VPC_CIDR:?LAB_VPC_CIDR이 필요합니다}"
: "${LAB_SUBNET_CIDR:?LAB_SUBNET_CIDR이 필요합니다}"
: "${LAB_VPC_ID:?LAB_VPC_ID가 필요합니다}"
: "${LAB_SUBNET_ID:?LAB_SUBNET_ID가 필요합니다}"
: "${LAB_IGW_ID:?LAB_IGW_ID가 필요합니다}"
: "${LAB_ROUTE_TABLE_ID:?LAB_ROUTE_TABLE_ID가 필요합니다}"

if [[ "$AWS_REGION" != "ap-northeast-2" ]]; then
  printf '검증 중단: 서울 리전(ap-northeast-2)이 아닙니다. 현재 값: %s\n' "$AWS_REGION" >&2
  exit 1
fi

if ! aws sts get-caller-identity \
  --query "contains(Arn, 'user/lab-cloud-web')" \
  --output text \
  --region "$AWS_REGION" \
  --no-cli-pager | grep -Eiq '^true$'; then
  printf '검증 중단: MFA 세션이 만료됐거나 lab-cloud-web 사용자가 아닙니다.\n' >&2
  printf '먼저 ./scripts/setup-aws-cli.sh를 실행하세요.\n' >&2
  exit 1
fi

mkdir -p "${LAB_LOG_FILE%/*}"
: > "$LAB_LOG_FILE"
chmod 600 "$LAB_LOG_FILE"

run_capture() {
  local lab_display="$1"
  shift
  local lab_output
  local lab_status

  set +e
  lab_output="$("$@" 2>&1)"
  lab_status=$?
  set -e

  {
    printf '\n[%s] $ %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$lab_display"
    printf '%s\n' "$lab_output"
    printf '[exit=%d]\n' "$lab_status"
  } | tee -a "$LAB_LOG_FILE" >&2

  if (( lab_status != 0 )); then
    return "$lab_status"
  fi

  printf '%s\n' "$lab_output"
}

run_logged() {
  local lab_display="$1"
  shift
  run_capture "$lab_display" "$@" >/dev/null
}

record_check() {
  local lab_name="$1"
  local lab_expected="$2"
  local lab_actual="$3"
  local lab_result

  if [[ "$lab_actual" == "$lab_expected" ]]; then
    lab_result="PASS"
  else
    lab_result="FAIL"
    LAB_FAILURES=$((LAB_FAILURES + 1))
  fi

  printf '[CHECK] %-34s expected=%-24s actual=%-24s %s\n' \
    "$lab_name" "$lab_expected" "$lab_actual" "$lab_result" | tee -a "$LAB_LOG_FILE"
}

printf '[%s] NETWORK VALIDATION START\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" | tee "$LAB_LOG_FILE"
printf 'region=%s project=%s\n' "$AWS_REGION" "$LAB_PROJECT" | tee -a "$LAB_LOG_FILE"

run_logged \
  "aws ec2 describe-vpcs --vpc-ids ${LAB_VPC_ID} <limited fields>" \
  aws ec2 describe-vpcs \
    --vpc-ids "$LAB_VPC_ID" \
    --query 'Vpcs[].{VpcId:VpcId,Cidr:CidrBlock,State:State,Project:Tags[?Key==`Project`].Value|[0]}' \
    --region "$AWS_REGION" \
    --no-cli-pager

run_logged \
  "aws ec2 describe-subnets --subnet-ids ${LAB_SUBNET_ID} <public subnet fields>" \
  aws ec2 describe-subnets \
    --subnet-ids "$LAB_SUBNET_ID" \
    --query 'Subnets[].{SubnetId:SubnetId,VpcId:VpcId,Cidr:CidrBlock,AZ:AvailabilityZone,State:State,PublicIpAutoAssign:MapPublicIpOnLaunch}' \
    --region "$AWS_REGION" \
    --no-cli-pager

run_logged \
  "aws ec2 describe-internet-gateways --internet-gateway-ids ${LAB_IGW_ID} <attachments>" \
  aws ec2 describe-internet-gateways \
    --internet-gateway-ids "$LAB_IGW_ID" \
    --query 'InternetGateways[].{InternetGatewayId:InternetGatewayId,Attachments:Attachments}' \
    --region "$AWS_REGION" \
    --no-cli-pager

run_logged \
  "aws ec2 describe-route-tables --route-table-ids ${LAB_ROUTE_TABLE_ID} <routes and associations>" \
  aws ec2 describe-route-tables \
    --route-table-ids "$LAB_ROUTE_TABLE_ID" \
    --query 'RouteTables[].{RouteTableId:RouteTableId,VpcId:VpcId,Routes:Routes[].{Destination:DestinationCidrBlock,Target:GatewayId,State:State},Associations:Associations[].{SubnetId:SubnetId,AssociationId:RouteTableAssociationId}}' \
    --region "$AWS_REGION" \
    --no-cli-pager

LAB_ACTUAL_VPC_CIDR="$(aws ec2 describe-vpcs \
  --vpc-ids "$LAB_VPC_ID" --query 'Vpcs[0].CidrBlock' \
  --output text --region "$AWS_REGION" --no-cli-pager)"
LAB_ACTUAL_VPC_STATE="$(aws ec2 describe-vpcs \
  --vpc-ids "$LAB_VPC_ID" --query 'Vpcs[0].State' \
  --output text --region "$AWS_REGION" --no-cli-pager)"
LAB_ACTUAL_VPC_PROJECT="$(aws ec2 describe-vpcs \
  --vpc-ids "$LAB_VPC_ID" --query 'Vpcs[0].Tags[?Key==`Project`].Value | [0]' \
  --output text --region "$AWS_REGION" --no-cli-pager)"

LAB_ACTUAL_SUBNET_VPC="$(aws ec2 describe-subnets \
  --subnet-ids "$LAB_SUBNET_ID" --query 'Subnets[0].VpcId' \
  --output text --region "$AWS_REGION" --no-cli-pager)"
LAB_ACTUAL_SUBNET_CIDR="$(aws ec2 describe-subnets \
  --subnet-ids "$LAB_SUBNET_ID" --query 'Subnets[0].CidrBlock' \
  --output text --region "$AWS_REGION" --no-cli-pager)"
LAB_ACTUAL_SUBNET_STATE="$(aws ec2 describe-subnets \
  --subnet-ids "$LAB_SUBNET_ID" --query 'Subnets[0].State' \
  --output text --region "$AWS_REGION" --no-cli-pager)"
LAB_ACTUAL_PUBLIC_IP_ASSIGN="$(aws ec2 describe-subnets \
  --subnet-ids "$LAB_SUBNET_ID" --query 'Subnets[0].MapPublicIpOnLaunch' \
  --output text --region "$AWS_REGION" --no-cli-pager | tr '[:upper:]' '[:lower:]')"

LAB_ACTUAL_IGW_ATTACHMENT_COUNT="$(aws ec2 describe-internet-gateways \
  --internet-gateway-ids "$LAB_IGW_ID" \
  --query "length(InternetGateways[0].Attachments[?VpcId=='${LAB_VPC_ID}' && State=='available'])" \
  --output text --region "$AWS_REGION" --no-cli-pager)"

LAB_ACTUAL_ROUTE_TABLE_VPC="$(aws ec2 describe-route-tables \
  --route-table-ids "$LAB_ROUTE_TABLE_ID" --query 'RouteTables[0].VpcId' \
  --output text --region "$AWS_REGION" --no-cli-pager)"
LAB_ACTUAL_LOCAL_ROUTE_COUNT="$(aws ec2 describe-route-tables \
  --route-table-ids "$LAB_ROUTE_TABLE_ID" \
  --query "length(RouteTables[0].Routes[?DestinationCidrBlock=='${LAB_VPC_CIDR}' && GatewayId=='local' && State=='active'])" \
  --output text --region "$AWS_REGION" --no-cli-pager)"
LAB_ACTUAL_DEFAULT_ROUTE_COUNT="$(aws ec2 describe-route-tables \
  --route-table-ids "$LAB_ROUTE_TABLE_ID" \
  --query "length(RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0' && GatewayId=='${LAB_IGW_ID}' && State=='active'])" \
  --output text --region "$AWS_REGION" --no-cli-pager)"
LAB_ACTUAL_SUBNET_ASSOCIATION_COUNT="$(aws ec2 describe-route-tables \
  --route-table-ids "$LAB_ROUTE_TABLE_ID" \
  --query "length(RouteTables[0].Associations[?SubnetId=='${LAB_SUBNET_ID}'])" \
  --output text --region "$AWS_REGION" --no-cli-pager)"

LAB_FAILURES=0
printf '\nVALIDATION SUMMARY\n' | tee -a "$LAB_LOG_FILE"
record_check 'VPC_CIDR_CHECK' "$LAB_VPC_CIDR" "$LAB_ACTUAL_VPC_CIDR"
record_check 'VPC_STATE_CHECK' 'available' "$LAB_ACTUAL_VPC_STATE"
record_check 'VPC_PROJECT_TAG_CHECK' "$LAB_PROJECT" "$LAB_ACTUAL_VPC_PROJECT"
record_check 'SUBNET_VPC_CHECK' "$LAB_VPC_ID" "$LAB_ACTUAL_SUBNET_VPC"
record_check 'SUBNET_CIDR_CHECK' "$LAB_SUBNET_CIDR" "$LAB_ACTUAL_SUBNET_CIDR"
record_check 'SUBNET_STATE_CHECK' 'available' "$LAB_ACTUAL_SUBNET_STATE"
record_check 'SUBNET_PUBLIC_IP_CHECK' 'true' "$LAB_ACTUAL_PUBLIC_IP_ASSIGN"
record_check 'IGW_ATTACHMENT_CHECK' '1' "$LAB_ACTUAL_IGW_ATTACHMENT_COUNT"
record_check 'ROUTE_TABLE_VPC_CHECK' "$LAB_VPC_ID" "$LAB_ACTUAL_ROUTE_TABLE_VPC"
record_check 'LOCAL_ROUTE_CHECK' '1' "$LAB_ACTUAL_LOCAL_ROUTE_COUNT"
record_check 'DEFAULT_ROUTE_CHECK' '1' "$LAB_ACTUAL_DEFAULT_ROUTE_COUNT"
record_check 'SUBNET_ROUTE_ASSOCIATION_CHECK' '1' "$LAB_ACTUAL_SUBNET_ASSOCIATION_COUNT"

if (( LAB_FAILURES == 0 )); then
  printf 'NETWORK_VALIDATION=PASS\n' | tee -a "$LAB_LOG_FILE"
  printf '네트워크 검증 완료: PASS\n'
  printf '로그: %s\n' "$LAB_LOG_FILE"
  exit 0
fi

printf 'NETWORK_VALIDATION=FAIL failures=%d\n' "$LAB_FAILURES" | tee -a "$LAB_LOG_FILE"
printf '네트워크 검증 실패: %d개 항목을 확인하세요.\n' "$LAB_FAILURES" >&2
printf '로그: %s\n' "$LAB_LOG_FILE" >&2
exit 1

