#!/usr/bin/env bash

set -euo pipefail
umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"
BEFORE_LOG="$ROOT_DIR/docs/evidence/logs/08-cleanup-before.log"
AFTER_LOG="$ROOT_DIR/docs/evidence/logs/09-cleanup-after.log"

# 삭제 전 필요한 프로그램과 AWS EC2 호출 형식을 공통화한다.
need() {
  command -v "$1" >/dev/null 2>&1 || { printf '필수 프로그램을 찾을 수 없습니다: %s\n' "$1" >&2; exit 1; }
}

aws_ec2() {
  aws ec2 "$@" --region "$AWS_REGION" --no-cli-pager
}

# 삭제 명령과 결과를 지정한 증거 로그에 기록한다.
capture() {
  local file="$1" display="$2" output status
  shift 2
  set +e
  output="$("$@" 2>&1)"
  status=$?
  set -e
  {
    printf '\n[%s] $ %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$display"
    printf '%s\n[exit=%d]\n' "$output" "$status"
  } | tee -a "$file" >&2
  (( status == 0 )) || return "$status"
  printf '%s\n' "$output"
}

logged() {
  local file="$1" display="$2"
  shift 2
  capture "$file" "$display" "$@" >/dev/null
}

note() {
  printf '\n[%s] %s\n[exit=0]\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$2" | tee -a "$1"
}

# 리소스 ID의 Project 태그를 조회해 다른 프로젝트 삭제를 방지한다.
project_tag() {
  local id="$1"
  [[ -n "$id" && "$id" != None ]] || return 0
  aws_ec2 describe-tags \
    --filters "Name=resource-id,Values=$id" 'Name=key,Values=Project' \
    --query 'Tags[0].Value' --output text 2>/dev/null || true
}

# ID가 없거나 이미 삭제된 대상은 건너뛰고, 소유 태그가 다르면 즉시 중단한다.
check_target() {
  local label="$1" id="$2" tag
  if [[ -z "$id" || "$id" == None ]]; then
    printf '  %-18s %-30s 건너뜀\n' "$label" '(ID 없음)'
    return 1
  fi
  tag="$(project_tag "$id")"
  if [[ -z "$tag" || "$tag" == None ]]; then
    printf '  %-18s %-30s 이미 없거나 태그 없음\n' "$label" "$id"
    return 1
  fi
  [[ "$tag" == "$LAB_PROJECT" ]] || { printf '삭제 중단: %s %s의 Project 태그가 %s입니다.\n' "$label" "$id" "$tag" >&2; exit 1; }
  printf '  %-18s %-30s Project=%s\n' "$label" "$id" "$tag"
  return 0
}

# 삭제 후 프로젝트 태그 기준 개수가 0인지 확인한다.
verify_zero() {
  local label="$1" display="$2" count
  shift 2
  count="$(capture "$AFTER_LOG" "$display" "$@")"
  [[ "$count" == 0 ]] || { printf '삭제 후 검증 실패: %s count=%s\n' "$label" "$count" >&2; exit 1; }
}

# 세션과 고정 리전·프로젝트를 검증한다. 별도 실행 모드는 허용하지 않는다.
(( $# == 0 )) || { printf '사용법: ./scripts/cleanup-server.sh\n' >&2; exit 2; }
for command in aws grep tee; do need "$command"; done
[[ -f "$ENV_FILE" ]] || { printf '.env를 찾을 수 없습니다.\n' >&2; exit 1; }
chmod 600 "$ENV_FILE"

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

for variable in AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_REGION LAB_PROJECT LAB_KEY_NAME; do
  [[ -n "${!variable:-}" ]] || { printf '필수 환경 변수가 없습니다: %s\n' "$variable" >&2; exit 1; }
done
[[ "$AWS_REGION" == ap-northeast-2 ]] || { printf '삭제 중단: 서울 리전이 아닙니다.\n' >&2; exit 1; }
[[ "$LAB_PROJECT" == codyssey-06-1 ]] || { printf '삭제 중단: 허용되지 않은 프로젝트입니다.\n' >&2; exit 1; }

CALLER="$(aws sts get-caller-identity --query "contains(Arn, 'user/lab-cloud-web')" \
  --output text --region "$AWS_REGION" --no-cli-pager)"
case "$CALLER" in True|true) ;; *) printf 'AWS 세션이 만료됐거나 호출자가 올바르지 않습니다.\n' >&2; exit 1 ;; esac

INSTANCE_ID="${LAB_INSTANCE_ID:-}"
VOLUME_ID="${LAB_VOLUME_ID:-}"
SG_ID="${LAB_SECURITY_GROUP_ID:-}"
ROUTE_ID="${LAB_ROUTE_TABLE_ID:-}"
SUBNET_ID="${LAB_SUBNET_ID:-}"
IGW_ID="${LAB_IGW_ID:-}"
VPC_ID="${LAB_VPC_ID:-}"
PRIVATE_KEY="$ROOT_DIR/.secrets/${LAB_KEY_NAME}.pem"

# .env의 각 ID가 실제로 이 실습 프로젝트에 속하는지 먼저 표시한다.
printf '삭제 범위 사전 검사\n  리전: %s\n  프로젝트: %s\n' "$AWS_REGION" "$LAB_PROJECT"
INSTANCE_OK=0; check_target instance "$INSTANCE_ID" && INSTANCE_OK=1
VOLUME_OK=0; check_target volume "$VOLUME_ID" && VOLUME_OK=1
SG_OK=0; check_target security-group "$SG_ID" && SG_OK=1
ROUTE_OK=0; check_target route-table "$ROUTE_ID" && ROUTE_OK=1
SUBNET_OK=0; check_target subnet "$SUBNET_ID" && SUBNET_OK=1
IGW_OK=0; check_target internet-gateway "$IGW_ID" && IGW_OK=1
VPC_OK=0; check_target vpc "$VPC_ID" && VPC_OK=1

KEY_TAG="$(aws_ec2 describe-key-pairs --key-names "$LAB_KEY_NAME" \
  --query 'KeyPairs[0].Tags[?Key==`Project`].Value | [0]' --output text 2>/dev/null || true)"
KEY_OK=0
if [[ -n "$KEY_TAG" && "$KEY_TAG" != None ]]; then
  [[ "$KEY_TAG" == "$LAB_PROJECT" ]] || { printf '삭제 중단: Key Pair의 Project 태그가 일치하지 않습니다.\n' >&2; exit 1; }
  KEY_OK=1
  printf '  %-18s %-30s Project=%s\n' key-pair "$LAB_KEY_NAME" "$KEY_TAG"
else
  printf '  %-18s %-30s 이미 없음\n' key-pair "$LAB_KEY_NAME"
fi
printf '  %-18s %-30s 생성 대상 아님, 삭제 후 0개 검증\n' elastic-ip '(Project 태그)'

# 프로젝트명을 정확히 다시 입력한 경우에만 로그 생성과 실제 삭제를 시작한다.
printf '\n경고: 위 AWS 서버 리소스와 로컬 SSH Private Key를 삭제합니다.\n'
read -r -p "계속하려면 '${LAB_PROJECT}'를 입력하세요: " CONFIRMATION
[[ "$CONFIRMATION" == "$LAB_PROJECT" ]] || { printf '확인 문구가 일치하지 않아 삭제를 취소했습니다.\n' >&2; exit 1; }
unset CONFIRMATION

mkdir -p "${BEFORE_LOG%/*}"
: > "$BEFORE_LOG"
: > "$AFTER_LOG"
chmod 600 "$BEFORE_LOG" "$AFTER_LOG"
note "$BEFORE_LOG" "cleanup targets: instance=$INSTANCE_ID volume=$VOLUME_ID key=$LAB_KEY_NAME sg=$SG_ID route=$ROUTE_ID subnet=$SUBNET_ID igw=$IGW_ID vpc=$VPC_ID"

# EC2를 먼저 종료하고 루트 EBS가 자동 삭제되지 않았을 때만 직접 삭제한다.
if (( INSTANCE_OK )); then
  STATE="$(aws_ec2 describe-instances --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].State.Name' --output text)"
  if [[ "$STATE" != terminated ]]; then
    logged "$BEFORE_LOG" "aws ec2 terminate-instances --instance-ids $INSTANCE_ID" \
      aws_ec2 terminate-instances --instance-ids "$INSTANCE_ID"
    logged "$BEFORE_LOG" "aws ec2 wait instance-terminated --instance-ids $INSTANCE_ID" \
      aws_ec2 wait instance-terminated --instance-ids "$INSTANCE_ID"
  fi
else
  note "$BEFORE_LOG" 'EC2 already absent or unmanaged'
fi

if (( VOLUME_OK )); then
  STATE="$(aws_ec2 describe-volumes --volume-ids "$VOLUME_ID" --query 'Volumes[0].State' --output text 2>/dev/null || true)"
  case "$STATE" in
    available)
      logged "$BEFORE_LOG" "aws ec2 delete-volume --volume-id $VOLUME_ID" aws_ec2 delete-volume --volume-id "$VOLUME_ID"
      logged "$BEFORE_LOG" "aws ec2 wait volume-deleted --volume-ids $VOLUME_ID" aws_ec2 wait volume-deleted --volume-ids "$VOLUME_ID"
      ;;
    deleting)
      logged "$BEFORE_LOG" "aws ec2 wait volume-deleted --volume-ids $VOLUME_ID" aws_ec2 wait volume-deleted --volume-ids "$VOLUME_ID"
      ;;
    in-use) printf '삭제 중단: EC2 종료 후에도 EBS가 사용 중입니다.\n' >&2; exit 1 ;;
    *) note "$BEFORE_LOG" "EBS deleted automatically or already absent: $VOLUME_ID" ;;
  esac
fi

# AWS Key Pair와 대응하는 로컬 Private Key를 함께 정리한다.
if (( KEY_OK )); then
  logged "$BEFORE_LOG" "aws ec2 delete-key-pair --key-name $LAB_KEY_NAME" aws_ec2 delete-key-pair --key-name "$LAB_KEY_NAME"
fi
if [[ -f "$PRIVATE_KEY" ]]; then
  rm -f -- "$PRIVATE_KEY"
  note "$BEFORE_LOG" "local SSH Private Key deleted: .secrets/$LAB_KEY_NAME.pem"
fi

# ENI 해제 지연을 고려해 Security Group 삭제만 제한적으로 재시도한다.
if (( SG_OK )); then
  SG_DELETED=false
  for attempt in {1..12}; do
    set +e
    OUTPUT="$(aws_ec2 delete-security-group --group-id "$SG_ID" 2>&1)"
    STATUS=$?
    set -e
    {
      printf '\n[%s] $ aws ec2 delete-security-group --group-id %s <attempt %d/12>\n' \
        "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$SG_ID" "$attempt"
      printf '%s\n[exit=%d]\n' "$OUTPUT" "$STATUS"
    } | tee -a "$BEFORE_LOG"
    if (( STATUS == 0 )); then SG_DELETED=true; break; fi
    grep -q DependencyViolation <<< "$OUTPUT" || { printf 'Security Group 삭제에 실패했습니다.\n' >&2; exit "$STATUS"; }
    sleep 5
  done
  [[ "$SG_DELETED" == true ]] || { printf 'Security Group 종속성이 해제되지 않았습니다.\n' >&2; exit 1; }
fi

# Route Table 연결부터 해제한 뒤 Subnet, IGW, VPC를 종속성 역순으로 삭제한다.
if (( ROUTE_OK )); then
  ASSOCIATION_ID="$(aws_ec2 describe-route-tables --route-table-ids "$ROUTE_ID" \
    --query "RouteTables[0].Associations[?SubnetId=='$SUBNET_ID'].RouteTableAssociationId | [0]" --output text)"
  if [[ -n "$ASSOCIATION_ID" && "$ASSOCIATION_ID" != None ]]; then
    logged "$BEFORE_LOG" "aws ec2 disassociate-route-table --association-id $ASSOCIATION_ID" \
      aws_ec2 disassociate-route-table --association-id "$ASSOCIATION_ID"
  fi
  logged "$BEFORE_LOG" "aws ec2 delete-route-table --route-table-id $ROUTE_ID" \
    aws_ec2 delete-route-table --route-table-id "$ROUTE_ID"
fi

if (( SUBNET_OK )); then
  logged "$BEFORE_LOG" "aws ec2 delete-subnet --subnet-id $SUBNET_ID" aws_ec2 delete-subnet --subnet-id "$SUBNET_ID"
fi
if (( IGW_OK )); then
  ATTACHED_VPC="$(aws_ec2 describe-internet-gateways --internet-gateway-ids "$IGW_ID" \
    --query 'InternetGateways[0].Attachments[0].VpcId' --output text)"
  if [[ "$ATTACHED_VPC" == "$VPC_ID" ]]; then
    logged "$BEFORE_LOG" "aws ec2 detach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID" \
      aws_ec2 detach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"
  fi
  logged "$BEFORE_LOG" "aws ec2 delete-internet-gateway --internet-gateway-id $IGW_ID" \
    aws_ec2 delete-internet-gateway --internet-gateway-id "$IGW_ID"
fi
if (( VPC_OK )); then
  logged "$BEFORE_LOG" "aws ec2 delete-vpc --vpc-id $VPC_ID" aws_ec2 delete-vpc --vpc-id "$VPC_ID"
fi

# 생성한 모든 리소스와 미사용 EIP가 남지 않았는지 태그 기준으로 최종 확인한다.
verify_zero 'active EC2' 'aws ec2 describe-instances <active project count>' \
  aws_ec2 describe-instances --filters "Name=tag:Project,Values=$LAB_PROJECT" \
    'Name=instance-state-name,Values=pending,running,shutting-down,stopping,stopped' \
    --query 'length(Reservations[].Instances[])' --output text
verify_zero EBS 'aws ec2 describe-volumes <project count>' \
  aws_ec2 describe-volumes --filters "Name=tag:Project,Values=$LAB_PROJECT" --query 'length(Volumes)' --output text
verify_zero EIP 'aws ec2 describe-addresses <project count>' \
  aws_ec2 describe-addresses --filters "Name=tag:Project,Values=$LAB_PROJECT" --query 'length(Addresses)' --output text
verify_zero 'Key Pair' 'aws ec2 describe-key-pairs <project count>' \
  aws_ec2 describe-key-pairs --filters "Name=tag:Project,Values=$LAB_PROJECT" --query 'length(KeyPairs)' --output text
verify_zero SG 'aws ec2 describe-security-groups <project count>' \
  aws_ec2 describe-security-groups --filters "Name=tag:Project,Values=$LAB_PROJECT" --query 'length(SecurityGroups)' --output text
verify_zero 'Route Table' 'aws ec2 describe-route-tables <project count>' \
  aws_ec2 describe-route-tables --filters "Name=tag:Project,Values=$LAB_PROJECT" --query 'length(RouteTables)' --output text
verify_zero Subnet 'aws ec2 describe-subnets <project count>' \
  aws_ec2 describe-subnets --filters "Name=tag:Project,Values=$LAB_PROJECT" --query 'length(Subnets)' --output text
verify_zero IGW 'aws ec2 describe-internet-gateways <project count>' \
  aws_ec2 describe-internet-gateways --filters "Name=tag:Project,Values=$LAB_PROJECT" --query 'length(InternetGateways)' --output text
verify_zero VPC 'aws ec2 describe-vpcs <project count>' \
  aws_ec2 describe-vpcs --filters "Name=tag:Project,Values=$LAB_PROJECT" --query 'length(Vpcs)' --output text

note "$AFTER_LOG" 'cleanup_status=PASS; IAM credentials and .env intentionally retained'
printf '\nAWS 서버 리소스 삭제 및 검증 완료\n  삭제 로그: %s\n  검증 로그: %s\n' "$BEFORE_LOG" "$AFTER_LOG"
