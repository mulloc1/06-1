#!/usr/bin/env bash

set -euo pipefail
umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"
LOG_FILE="$ROOT_DIR/docs/evidence/logs/02-network-validation.log"

# 읽기 전용 검증에 필요한 공통 명령 형식을 정의한다.
need() {
  command -v "$1" >/dev/null 2>&1 || { printf '필수 프로그램을 찾을 수 없습니다: %s\n' "$1" >&2; exit 1; }
}

aws_ec2() {
  aws ec2 "$@" --region "$AWS_REGION" --no-cli-pager
}

# 각 AWS 조회를 한 번만 실행하고 원본 결과를 검증 로그에 남긴다.
capture() {
  local display="$1" output status
  shift
  set +e
  output="$("$@" 2>&1)"
  status=$?
  set -e
  {
    printf '\n[%s] $ %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$display"
    printf '%s\n[exit=%d]\n' "$output" "$status"
  } | tee -a "$LOG_FILE" >&2
  (( status == 0 )) || return "$status"
  printf '%s\n' "$output"
}

# 기대값과 실제값을 비교해 누적 실패 수와 PASS/FAIL을 기록한다.
check() {
  local name="$1" expected="$2" actual="$3" result=PASS
  if [[ "$actual" != "$expected" ]]; then
    result=FAIL
    FAILURES=$((FAILURES + 1))
  fi
  printf '[CHECK] %-32s expected=%-20s actual=%-20s %s\n' \
    "$name" "$expected" "$actual" "$result" | tee -a "$LOG_FILE"
}

# 환경 파일과 MFA 세션을 확인하고 기존 검증 로그를 최신 실행으로 교체한다.
(( $# == 0 )) || { printf '사용법: ./scripts/verify-network.sh\n' >&2; exit 2; }
for command in aws tee tr; do need "$command"; done
[[ -f "$ENV_FILE" ]] || { printf '.env를 찾을 수 없습니다.\n' >&2; exit 1; }

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

for variable in AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_REGION LAB_PROJECT \
  LAB_VPC_CIDR LAB_SUBNET_CIDR LAB_VPC_ID LAB_SUBNET_ID LAB_IGW_ID LAB_ROUTE_TABLE_ID; do
  [[ -n "${!variable:-}" ]] || { printf '필수 환경 변수가 없습니다: %s\n' "$variable" >&2; exit 1; }
done
[[ "$AWS_REGION" == ap-northeast-2 ]] || { printf '서울 리전(ap-northeast-2)만 검증할 수 있습니다.\n' >&2; exit 1; }

CALLER="$(aws sts get-caller-identity --query "contains(Arn, 'user/lab-cloud-web')" \
  --output text --region "$AWS_REGION" --no-cli-pager)"
case "$CALLER" in True|true) ;; *) printf 'AWS 세션이 만료됐거나 호출자가 올바르지 않습니다.\n' >&2; exit 1 ;; esac

mkdir -p "${LOG_FILE%/*}"
: > "$LOG_FILE"
chmod 600 "$LOG_FILE"
printf '[%s] NETWORK VALIDATION START\nregion=%s project=%s\n' \
  "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$AWS_REGION" "$LAB_PROJECT" | tee "$LOG_FILE"

# VPC, Subnet, IGW, Route Table을 각각 한 번 조회해 이후 판정에 재사용한다.
VPC_ROW="$(capture "aws ec2 describe-vpcs --vpc-ids $LAB_VPC_ID <id, cidr, state, project>" \
  aws_ec2 describe-vpcs --vpc-ids "$LAB_VPC_ID" \
    --query 'Vpcs[0].[VpcId,CidrBlock,State,Tags[?Key==`Project`].Value|[0]]' --output text)"
read -r VPC_ID VPC_CIDR VPC_STATE VPC_PROJECT <<< "$VPC_ROW"

SUBNET_ROW="$(capture "aws ec2 describe-subnets --subnet-ids $LAB_SUBNET_ID <public subnet fields>" \
  aws_ec2 describe-subnets --subnet-ids "$LAB_SUBNET_ID" \
    --query 'Subnets[0].[SubnetId,VpcId,CidrBlock,State,MapPublicIpOnLaunch,AvailabilityZone]' --output text)"
read -r SUBNET_ID SUBNET_VPC SUBNET_CIDR SUBNET_STATE SUBNET_PUBLIC_IP SUBNET_AZ <<< "$SUBNET_ROW"
SUBNET_PUBLIC_IP="$(printf '%s' "$SUBNET_PUBLIC_IP" | tr '[:upper:]' '[:lower:]')"

IGW_ROW="$(capture "aws ec2 describe-internet-gateways --internet-gateway-ids $LAB_IGW_ID <attachment>" \
  aws_ec2 describe-internet-gateways --internet-gateway-ids "$LAB_IGW_ID" \
    --query 'InternetGateways[0].[InternetGatewayId,Attachments[0].VpcId,Attachments[0].State]' --output text)"
read -r IGW_ID IGW_VPC IGW_STATE <<< "$IGW_ROW"

ROUTE_ROW="$(capture "aws ec2 describe-route-tables --route-table-ids $LAB_ROUTE_TABLE_ID <routes and association>" \
  aws_ec2 describe-route-tables --route-table-ids "$LAB_ROUTE_TABLE_ID" \
    --query "RouteTables[0].[RouteTableId,VpcId,length(Routes[?DestinationCidrBlock=='$LAB_VPC_CIDR' && GatewayId=='local' && State=='active']),length(Routes[?DestinationCidrBlock=='0.0.0.0/0' && GatewayId=='$LAB_IGW_ID' && State=='active']),length(Associations[?SubnetId=='$LAB_SUBNET_ID'])]" \
    --output text)"
read -r ROUTE_ID ROUTE_VPC LOCAL_ROUTES DEFAULT_ROUTES SUBNET_ASSOCIATIONS <<< "$ROUTE_ROW"

# 네트워크 구조·상태·태그·라우팅·연결 관계를 평가한다.
FAILURES=0
printf '\nVALIDATION SUMMARY\n' | tee -a "$LOG_FILE"
check VPC_ID "$LAB_VPC_ID" "$VPC_ID"
check VPC_CIDR "$LAB_VPC_CIDR" "$VPC_CIDR"
check VPC_STATE available "$VPC_STATE"
check VPC_PROJECT_TAG "$LAB_PROJECT" "$VPC_PROJECT"
check SUBNET_ID "$LAB_SUBNET_ID" "$SUBNET_ID"
check SUBNET_VPC "$LAB_VPC_ID" "$SUBNET_VPC"
check SUBNET_CIDR "$LAB_SUBNET_CIDR" "$SUBNET_CIDR"
check SUBNET_STATE available "$SUBNET_STATE"
check SUBNET_PUBLIC_IP true "$SUBNET_PUBLIC_IP"
check IGW_ID "$LAB_IGW_ID" "$IGW_ID"
check IGW_VPC "$LAB_VPC_ID" "$IGW_VPC"
check IGW_STATE available "$IGW_STATE"
check ROUTE_TABLE_ID "$LAB_ROUTE_TABLE_ID" "$ROUTE_ID"
check ROUTE_TABLE_VPC "$LAB_VPC_ID" "$ROUTE_VPC"
check LOCAL_ROUTE 1 "$LOCAL_ROUTES"
check DEFAULT_ROUTE 1 "$DEFAULT_ROUTES"
check SUBNET_ASSOCIATION 1 "$SUBNET_ASSOCIATIONS"

if (( FAILURES == 0 )); then
  printf 'NETWORK_VALIDATION=PASS\n' | tee -a "$LOG_FILE"
  exit 0
fi
printf 'NETWORK_VALIDATION=FAIL failures=%d\n' "$FAILURES" | tee -a "$LOG_FILE"
exit 1
