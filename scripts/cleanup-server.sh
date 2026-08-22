#!/usr/bin/env bash

set -euo pipefail
set -o pipefail
umask 077

LAB_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LAB_REPO_ROOT="$(cd -- "${LAB_SCRIPT_DIR}/.." && pwd)"
LAB_ENV_FILE="${LAB_REPO_ROOT}/.env"
LAB_BEFORE_LOG="${LAB_REPO_ROOT}/docs/evidence/logs/08-cleanup-before.log"
LAB_AFTER_LOG="${LAB_REPO_ROOT}/docs/evidence/logs/09-cleanup-after.log"
LAB_MODE="plan"

usage() {
  cat <<'EOF'
사용법:
  ./scripts/cleanup-server.sh             삭제 대상 조회만 수행
  ./scripts/cleanup-server.sh execute     확인 문구 입력 후 실제 삭제
  ./scripts/cleanup-server.sh --execute   위 명령과 동일
  ./scripts/cleanup-server.sh --help      도움말 표시

실제 삭제 범위:
  EC2, EBS, AWS Key Pair, Security Group, Route Table 연결/경로/테이블,
  Public Subnet, Internet Gateway, VPC, 대응하는 로컬 SSH Private Key

삭제하지 않는 항목:
  IAM 사용자·정책·MFA·Access Key, 로컬 .env
EOF
}

case "${1:-}" in
  ""|plan|--plan)
    LAB_MODE="plan"
    ;;
  execute|--execute)
    LAB_MODE="execute"
    ;;
  help|--help|-h)
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
  printf '옵션은 하나만 지정할 수 있습니다.\n\n' >&2
  usage >&2
  exit 2
fi

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf '필수 프로그램을 찾을 수 없습니다: %s\n' "$1" >&2
    exit 1
  fi
}

require_command aws
require_command awk
require_command date
require_command grep
require_command mktemp
require_command seq
require_command tee

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
: "${LAB_KEY_NAME:?LAB_KEY_NAME이 필요합니다}"

LAB_PRIVATE_KEY_PATH="${LAB_REPO_ROOT}/.secrets/${LAB_KEY_NAME}.pem"

if [[ "$AWS_REGION" != "ap-northeast-2" ]]; then
  printf '삭제 중단: 서울 리전(ap-northeast-2)이 아닙니다. 현재 값: %s\n' "$AWS_REGION" >&2
  exit 1
fi

if [[ "$LAB_PROJECT" != "codyssey-06-1" ]]; then
  printf '삭제 중단: 허용된 프로젝트 태그가 아닙니다. 현재 값: %s\n' "$LAB_PROJECT" >&2
  exit 1
fi

if ! aws sts get-caller-identity \
  --query "contains(Arn, 'user/lab-cloud-web')" \
  --output text \
  --region "$AWS_REGION" \
  --no-cli-pager | grep -Eiq '^true$'; then
  printf '삭제 중단: MFA 세션이 만료됐거나 lab-cloud-web 사용자가 아닙니다.\n' >&2
  printf '먼저 ./scripts/setup-aws-cli.sh를 실행하세요.\n' >&2
  exit 1
fi

resource_project_tag() {
  local lab_type="$1"
  local lab_id="$2"

  case "$lab_type" in
    instance)
      aws ec2 describe-instances \
        --filters Name=instance-id,Values="$lab_id" \
        --query 'Reservations[0].Instances[0].Tags[?Key==`Project`].Value | [0]' \
        --output text --region "$AWS_REGION" --no-cli-pager
      ;;
    volume)
      aws ec2 describe-volumes \
        --filters Name=volume-id,Values="$lab_id" \
        --query 'Volumes[0].Tags[?Key==`Project`].Value | [0]' \
        --output text --region "$AWS_REGION" --no-cli-pager
      ;;
    key-pair)
      aws ec2 describe-key-pairs \
        --filters Name=key-name,Values="$lab_id" \
        --query 'KeyPairs[0].Tags[?Key==`Project`].Value | [0]' \
        --output text --region "$AWS_REGION" --no-cli-pager
      ;;
    security-group)
      aws ec2 describe-security-groups \
        --filters Name=group-id,Values="$lab_id" \
        --query 'SecurityGroups[0].Tags[?Key==`Project`].Value | [0]' \
        --output text --region "$AWS_REGION" --no-cli-pager
      ;;
    route-table)
      aws ec2 describe-route-tables \
        --filters Name=route-table-id,Values="$lab_id" \
        --query 'RouteTables[0].Tags[?Key==`Project`].Value | [0]' \
        --output text --region "$AWS_REGION" --no-cli-pager
      ;;
    subnet)
      aws ec2 describe-subnets \
        --filters Name=subnet-id,Values="$lab_id" \
        --query 'Subnets[0].Tags[?Key==`Project`].Value | [0]' \
        --output text --region "$AWS_REGION" --no-cli-pager
      ;;
    internet-gateway)
      aws ec2 describe-internet-gateways \
        --filters Name=internet-gateway-id,Values="$lab_id" \
        --query 'InternetGateways[0].Tags[?Key==`Project`].Value | [0]' \
        --output text --region "$AWS_REGION" --no-cli-pager
      ;;
    vpc)
      aws ec2 describe-vpcs \
        --filters Name=vpc-id,Values="$lab_id" \
        --query 'Vpcs[0].Tags[?Key==`Project`].Value | [0]' \
        --output text --region "$AWS_REGION" --no-cli-pager
      ;;
    *)
      printf '지원하지 않는 리소스 유형: %s\n' "$lab_type" >&2
      return 2
      ;;
  esac
}

assert_owned_or_absent() {
  local lab_type="$1"
  local lab_id="$2"
  local lab_tag

  if [[ -z "$lab_id" || "$lab_id" == "None" ]]; then
    printf '삭제 중단: %s ID가 .env에 없습니다.\n' "$lab_type" >&2
    exit 1
  fi

  lab_tag="$(resource_project_tag "$lab_type" "$lab_id")"
  if [[ -z "$lab_tag" || "$lab_tag" == "None" ]]; then
    printf '  %-18s %-32s 이미 없거나 조회되지 않음\n' "$lab_type" "$lab_id"
    return 0
  fi

  if [[ "$lab_tag" != "$LAB_PROJECT" ]]; then
    printf '삭제 중단: %s %s의 Project 태그가 일치하지 않습니다: %s\n' \
      "$lab_type" "$lab_id" "$lab_tag" >&2
    exit 1
  fi

  printf '  %-18s %-32s Project=%s 확인\n' "$lab_type" "$lab_id" "$lab_tag"
}

printf '삭제 범위 사전 검사\n'
printf '  리전: %s\n' "$AWS_REGION"
printf '  프로젝트: %s\n' "$LAB_PROJECT"

assert_owned_or_absent instance "${LAB_INSTANCE_ID:-}"
assert_owned_or_absent volume "${LAB_VOLUME_ID:-}"
assert_owned_or_absent key-pair "$LAB_KEY_NAME"
assert_owned_or_absent security-group "${LAB_SECURITY_GROUP_ID:-}"
assert_owned_or_absent route-table "${LAB_ROUTE_TABLE_ID:-}"
assert_owned_or_absent subnet "${LAB_SUBNET_ID:-}"
assert_owned_or_absent internet-gateway "${LAB_IGW_ID:-}"
assert_owned_or_absent vpc "${LAB_VPC_ID:-}"

printf '  %-18s %-32s core 범위에서 생성하지 않음\n' \
  'elastic-ip' 'Project 태그 조회로 없음 확인'

if [[ "$LAB_MODE" == "plan" ]]; then
  printf '\n조회만 완료했습니다. AWS 리소스나 로그 파일은 변경하지 않았습니다.\n'
  printf '실제 삭제: ./scripts/cleanup-server.sh --execute\n'
  exit 0
fi

printf '\n경고: 외부 웹 URL이 사라지고 위 AWS 리소스가 삭제됩니다.\n'
printf 'IAM 사용자와 로컬 .env/Private Key는 삭제하지 않습니다.\n'
read -r -p "계속하려면 '${LAB_PROJECT}'를 입력하세요: " LAB_CONFIRMATION

if [[ "$LAB_CONFIRMATION" != "$LAB_PROJECT" ]]; then
  unset LAB_CONFIRMATION
  printf '확인 문구가 일치하지 않아 삭제를 취소했습니다.\n' >&2
  exit 1
fi
unset LAB_CONFIRMATION

mkdir -p "${LAB_BEFORE_LOG%/*}"
: > "$LAB_BEFORE_LOG"
: > "$LAB_AFTER_LOG"
chmod 600 "$LAB_BEFORE_LOG" "$LAB_AFTER_LOG"

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
    printf '%s\n' "$lab_output"
    printf '[exit=%d]\n' "$lab_status"
  } | tee -a "$lab_log_file" >&2

  if (( lab_status != 0 )); then
    return "$lab_status"
  fi

  printf '%s\n' "$lab_output"
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

resource_exists() {
  local lab_type="$1"
  local lab_id="$2"
  local lab_tag

  lab_tag="$(resource_project_tag "$lab_type" "$lab_id")"
  [[ -n "$lab_tag" && "$lab_tag" != "None" ]]
}

log_before_state() {
  run_logged "$LAB_BEFORE_LOG" \
    'aws sts get-caller-identity <lab-cloud-web Boolean only>' \
    aws sts get-caller-identity \
      --query "contains(Arn, 'user/lab-cloud-web')" \
      --output text --region "$AWS_REGION" --no-cli-pager

  run_logged "$LAB_BEFORE_LOG" \
    'aws ec2 describe-instances <project instances before cleanup>' \
    aws ec2 describe-instances \
      --filters Name=tag:Project,Values="$LAB_PROJECT" \
      --query 'Reservations[].Instances[].{InstanceId:InstanceId,State:State.Name,PublicIpAddress:PublicIpAddress,VolumeIds:BlockDeviceMappings[].Ebs.VolumeId}' \
      --region "$AWS_REGION" --no-cli-pager

  run_logged "$LAB_BEFORE_LOG" \
    'aws ec2 describe-volumes <project volumes before cleanup>' \
    aws ec2 describe-volumes \
      --filters Name=tag:Project,Values="$LAB_PROJECT" \
      --query 'Volumes[].{VolumeId:VolumeId,State:State,SizeGiB:Size,Type:VolumeType}' \
      --region "$AWS_REGION" --no-cli-pager

  run_logged "$LAB_BEFORE_LOG" \
    'aws ec2 describe-addresses <project Elastic IPs before cleanup>' \
    aws ec2 describe-addresses \
      --filters Name=tag:Project,Values="$LAB_PROJECT" \
      --query 'Addresses[].{AllocationId:AllocationId,PublicIp:PublicIp,AssociationId:AssociationId}' \
      --region "$AWS_REGION" --no-cli-pager

  run_logged "$LAB_BEFORE_LOG" \
    'aws ec2 describe-key-pairs <project key pairs before cleanup>' \
    aws ec2 describe-key-pairs \
      --filters Name=tag:Project,Values="$LAB_PROJECT" \
      --query 'KeyPairs[].{KeyName:KeyName,KeyType:KeyType}' \
      --region "$AWS_REGION" --no-cli-pager

  run_logged "$LAB_BEFORE_LOG" \
    'aws ec2 describe-security-groups <project security groups before cleanup>' \
    aws ec2 describe-security-groups \
      --filters Name=tag:Project,Values="$LAB_PROJECT" \
      --query 'SecurityGroups[].{GroupId:GroupId,GroupName:GroupName,VpcId:VpcId}' \
      --region "$AWS_REGION" --no-cli-pager

  run_logged "$LAB_BEFORE_LOG" \
    'aws ec2 describe-route-tables <project route tables before cleanup>' \
    aws ec2 describe-route-tables \
      --filters Name=tag:Project,Values="$LAB_PROJECT" \
      --query 'RouteTables[].{RouteTableId:RouteTableId,VpcId:VpcId,Associations:Associations[].RouteTableAssociationId}' \
      --region "$AWS_REGION" --no-cli-pager

  run_logged "$LAB_BEFORE_LOG" \
    'aws ec2 describe-subnets <project subnets before cleanup>' \
    aws ec2 describe-subnets \
      --filters Name=tag:Project,Values="$LAB_PROJECT" \
      --query 'Subnets[].{SubnetId:SubnetId,VpcId:VpcId,CidrBlock:CidrBlock}' \
      --region "$AWS_REGION" --no-cli-pager

  run_logged "$LAB_BEFORE_LOG" \
    'aws ec2 describe-internet-gateways <project IGWs before cleanup>' \
    aws ec2 describe-internet-gateways \
      --filters Name=tag:Project,Values="$LAB_PROJECT" \
      --query 'InternetGateways[].{InternetGatewayId:InternetGatewayId,Attachments:Attachments}' \
      --region "$AWS_REGION" --no-cli-pager

  run_logged "$LAB_BEFORE_LOG" \
    'aws ec2 describe-vpcs <project VPCs before cleanup>' \
    aws ec2 describe-vpcs \
      --filters Name=tag:Project,Values="$LAB_PROJECT" \
      --query 'Vpcs[].{VpcId:VpcId,CidrBlock:CidrBlock,State:State}' \
      --region "$AWS_REGION" --no-cli-pager
}

log_before_state

if resource_exists instance "$LAB_INSTANCE_ID"; then
  LAB_INSTANCE_STATE="$(
    aws ec2 describe-instances \
      --filters Name=instance-id,Values="$LAB_INSTANCE_ID" \
      --query 'Reservations[0].Instances[0].State.Name' \
      --output text --region "$AWS_REGION" --no-cli-pager
  )"

  if [[ "$LAB_INSTANCE_STATE" != "terminated" ]]; then
    run_logged "$LAB_BEFORE_LOG" \
      "aws ec2 terminate-instances --instance-ids ${LAB_INSTANCE_ID}" \
      aws ec2 terminate-instances \
        --instance-ids "$LAB_INSTANCE_ID" \
        --region "$AWS_REGION" --no-cli-pager

    run_logged "$LAB_BEFORE_LOG" \
      "aws ec2 wait instance-terminated --instance-ids ${LAB_INSTANCE_ID}" \
      aws ec2 wait instance-terminated \
        --instance-ids "$LAB_INSTANCE_ID" \
        --region "$AWS_REGION" --no-cli-pager
  else
    log_note "$LAB_BEFORE_LOG" "EC2 already terminated: ${LAB_INSTANCE_ID}"
  fi
else
  log_note "$LAB_BEFORE_LOG" "EC2 already absent: ${LAB_INSTANCE_ID}"
fi

if resource_exists volume "$LAB_VOLUME_ID"; then
  LAB_VOLUME_STATE="$(
    aws ec2 describe-volumes \
      --filters Name=volume-id,Values="$LAB_VOLUME_ID" \
      --query 'Volumes[0].State' \
      --output text --region "$AWS_REGION" --no-cli-pager
  )"

  if [[ "$LAB_VOLUME_STATE" == "available" ]]; then
    run_logged "$LAB_BEFORE_LOG" \
      "aws ec2 delete-volume --volume-id ${LAB_VOLUME_ID} <DeleteOnTermination fallback>" \
      aws ec2 delete-volume \
        --volume-id "$LAB_VOLUME_ID" \
        --region "$AWS_REGION" --no-cli-pager
  elif [[ "$LAB_VOLUME_STATE" == "in-use" ]]; then
    printf '삭제 중단: EC2 종료 후에도 볼륨이 in-use입니다: %s\n' "$LAB_VOLUME_ID" >&2
    exit 1
  fi

  run_logged "$LAB_BEFORE_LOG" \
    "aws ec2 wait volume-deleted --volume-ids ${LAB_VOLUME_ID}" \
    aws ec2 wait volume-deleted \
      --volume-ids "$LAB_VOLUME_ID" \
      --region "$AWS_REGION" --no-cli-pager
else
  log_note "$LAB_BEFORE_LOG" "EBS deleted automatically with EC2: ${LAB_VOLUME_ID}"
fi

if resource_exists key-pair "$LAB_KEY_NAME"; then
  run_logged "$LAB_BEFORE_LOG" \
    "aws ec2 delete-key-pair --key-name ${LAB_KEY_NAME}" \
    aws ec2 delete-key-pair \
      --key-name "$LAB_KEY_NAME" \
      --region "$AWS_REGION" --no-cli-pager
else
  log_note "$LAB_BEFORE_LOG" "AWS Key Pair already absent: ${LAB_KEY_NAME}"
fi

if [[ -f "$LAB_PRIVATE_KEY_PATH" ]]; then
  rm -f -- "$LAB_PRIVATE_KEY_PATH"
  log_note "$LAB_BEFORE_LOG" "local SSH Private Key deleted: .secrets/${LAB_KEY_NAME}.pem"
else
  log_note "$LAB_BEFORE_LOG" "local SSH Private Key already absent: .secrets/${LAB_KEY_NAME}.pem"
fi

if resource_exists security-group "$LAB_SECURITY_GROUP_ID"; then
  LAB_SG_DELETED=false
  for LAB_SG_ATTEMPT in $(seq 1 12); do
    set +e
    LAB_SG_OUTPUT="$(
      aws ec2 delete-security-group \
        --group-id "$LAB_SECURITY_GROUP_ID" \
        --region "$AWS_REGION" --no-cli-pager 2>&1
    )"
    LAB_SG_STATUS=$?
    set -e

    {
      printf '\n[%s] $ aws ec2 delete-security-group --group-id %s <attempt %d/12>\n' \
        "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$LAB_SECURITY_GROUP_ID" "$LAB_SG_ATTEMPT"
      printf '%s\n' "$LAB_SG_OUTPUT"
      printf '[exit=%d]\n' "$LAB_SG_STATUS"
    } | tee -a "$LAB_BEFORE_LOG"

    if (( LAB_SG_STATUS == 0 )); then
      LAB_SG_DELETED=true
      break
    fi

    if grep -q 'DependencyViolation' <<< "$LAB_SG_OUTPUT"; then
      sleep 5
      continue
    fi

    printf 'Security Group 삭제에 실패했습니다. 로그를 확인하세요.\n' >&2
    exit "$LAB_SG_STATUS"
  done
  unset LAB_SG_OUTPUT

  if [[ "$LAB_SG_DELETED" != "true" ]]; then
    printf 'Security Group 종속 리소스가 제한 시간 안에 해제되지 않았습니다.\n' >&2
    exit 1
  fi
else
  log_note "$LAB_BEFORE_LOG" "Security Group already absent: ${LAB_SECURITY_GROUP_ID}"
fi

if resource_exists route-table "$LAB_ROUTE_TABLE_ID"; then
  LAB_ASSOCIATION_STATE="$(
    aws ec2 describe-route-tables \
      --route-table-ids "$LAB_ROUTE_TABLE_ID" \
      --query "RouteTables[0].Associations[?RouteTableAssociationId=='${LAB_ROUTE_ASSOCIATION_ID:-}'].AssociationState.State | [0]" \
      --output text --region "$AWS_REGION" --no-cli-pager
  )"

  if [[ -n "$LAB_ASSOCIATION_STATE" && "$LAB_ASSOCIATION_STATE" != "None" && "$LAB_ASSOCIATION_STATE" != "disassociated" ]]; then
    run_logged "$LAB_BEFORE_LOG" \
      "aws ec2 disassociate-route-table --association-id ${LAB_ROUTE_ASSOCIATION_ID}" \
      aws ec2 disassociate-route-table \
        --association-id "$LAB_ROUTE_ASSOCIATION_ID" \
        --region "$AWS_REGION" --no-cli-pager
  else
    log_note "$LAB_BEFORE_LOG" "Route Table association already absent: ${LAB_ROUTE_ASSOCIATION_ID:-unknown}"
  fi

  LAB_DEFAULT_ROUTE_COUNT="$(
    aws ec2 describe-route-tables \
      --route-table-ids "$LAB_ROUTE_TABLE_ID" \
      --query "length(RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0'])" \
      --output text --region "$AWS_REGION" --no-cli-pager
  )"

  if [[ "$LAB_DEFAULT_ROUTE_COUNT" != "0" ]]; then
    run_logged "$LAB_BEFORE_LOG" \
      "aws ec2 delete-route --route-table-id ${LAB_ROUTE_TABLE_ID} --destination-cidr-block 0.0.0.0/0" \
      aws ec2 delete-route \
        --route-table-id "$LAB_ROUTE_TABLE_ID" \
        --destination-cidr-block 0.0.0.0/0 \
        --region "$AWS_REGION" --no-cli-pager
  fi

  run_logged "$LAB_BEFORE_LOG" \
    "aws ec2 delete-route-table --route-table-id ${LAB_ROUTE_TABLE_ID}" \
    aws ec2 delete-route-table \
      --route-table-id "$LAB_ROUTE_TABLE_ID" \
      --region "$AWS_REGION" --no-cli-pager
else
  log_note "$LAB_BEFORE_LOG" "Route Table already absent: ${LAB_ROUTE_TABLE_ID}"
fi

if resource_exists subnet "$LAB_SUBNET_ID"; then
  run_logged "$LAB_BEFORE_LOG" \
    "aws ec2 delete-subnet --subnet-id ${LAB_SUBNET_ID}" \
    aws ec2 delete-subnet \
      --subnet-id "$LAB_SUBNET_ID" \
      --region "$AWS_REGION" --no-cli-pager
else
  log_note "$LAB_BEFORE_LOG" "Subnet already absent: ${LAB_SUBNET_ID}"
fi

if resource_exists internet-gateway "$LAB_IGW_ID"; then
  LAB_IGW_ATTACHED_VPC="$(
    aws ec2 describe-internet-gateways \
      --internet-gateway-ids "$LAB_IGW_ID" \
      --query 'InternetGateways[0].Attachments[0].VpcId' \
      --output text --region "$AWS_REGION" --no-cli-pager
  )"

  if [[ "$LAB_IGW_ATTACHED_VPC" == "$LAB_VPC_ID" ]]; then
    run_logged "$LAB_BEFORE_LOG" \
      "aws ec2 detach-internet-gateway --internet-gateway-id ${LAB_IGW_ID} --vpc-id ${LAB_VPC_ID}" \
      aws ec2 detach-internet-gateway \
        --internet-gateway-id "$LAB_IGW_ID" \
        --vpc-id "$LAB_VPC_ID" \
        --region "$AWS_REGION" --no-cli-pager
  fi

  run_logged "$LAB_BEFORE_LOG" \
    "aws ec2 delete-internet-gateway --internet-gateway-id ${LAB_IGW_ID}" \
    aws ec2 delete-internet-gateway \
      --internet-gateway-id "$LAB_IGW_ID" \
      --region "$AWS_REGION" --no-cli-pager
else
  log_note "$LAB_BEFORE_LOG" "Internet Gateway already absent: ${LAB_IGW_ID}"
fi

if resource_exists vpc "$LAB_VPC_ID"; then
  run_logged "$LAB_BEFORE_LOG" \
    "aws ec2 delete-vpc --vpc-id ${LAB_VPC_ID}" \
    aws ec2 delete-vpc \
      --vpc-id "$LAB_VPC_ID" \
      --region "$AWS_REGION" --no-cli-pager
else
  log_note "$LAB_BEFORE_LOG" "VPC already absent: ${LAB_VPC_ID}"
fi

verify_zero() {
  local lab_label="$1"
  local lab_display="$2"
  shift 2
  local lab_count

  lab_count="$(run_capture "$LAB_AFTER_LOG" "$lab_display" "$@")"
  if [[ "$lab_count" != "0" ]]; then
    printf '삭제 후 검증 실패: %s count=%s\n' "$lab_label" "$lab_count" >&2
    exit 1
  fi
}

verify_zero 'active EC2' \
  'aws ec2 describe-instances <active project instance count>' \
  aws ec2 describe-instances \
    --filters \
      Name=tag:Project,Values="$LAB_PROJECT" \
      Name=instance-state-name,Values=pending,running,shutting-down,stopping,stopped \
    --query 'length(Reservations[].Instances[])' \
    --output text --region "$AWS_REGION" --no-cli-pager

verify_zero 'EBS' \
  'aws ec2 describe-volumes <project volume count>' \
  aws ec2 describe-volumes \
    --filters Name=tag:Project,Values="$LAB_PROJECT" \
    --query 'length(Volumes)' \
    --output text --region "$AWS_REGION" --no-cli-pager

verify_zero 'Elastic IP' \
  'aws ec2 describe-addresses <project Elastic IP count>' \
  aws ec2 describe-addresses \
    --filters Name=tag:Project,Values="$LAB_PROJECT" \
    --query 'length(Addresses)' \
    --output text --region "$AWS_REGION" --no-cli-pager

verify_zero 'AWS Key Pair' \
  'aws ec2 describe-key-pairs <project key pair count>' \
  aws ec2 describe-key-pairs \
    --filters Name=tag:Project,Values="$LAB_PROJECT" \
    --query 'length(KeyPairs)' \
    --output text --region "$AWS_REGION" --no-cli-pager

verify_zero 'Security Group' \
  'aws ec2 describe-security-groups <project security group count>' \
  aws ec2 describe-security-groups \
    --filters Name=tag:Project,Values="$LAB_PROJECT" \
    --query 'length(SecurityGroups)' \
    --output text --region "$AWS_REGION" --no-cli-pager

verify_zero 'Route Table' \
  'aws ec2 describe-route-tables <project route table count>' \
  aws ec2 describe-route-tables \
    --filters Name=tag:Project,Values="$LAB_PROJECT" \
    --query 'length(RouteTables)' \
    --output text --region "$AWS_REGION" --no-cli-pager

verify_zero 'Subnet' \
  'aws ec2 describe-subnets <project subnet count>' \
  aws ec2 describe-subnets \
    --filters Name=tag:Project,Values="$LAB_PROJECT" \
    --query 'length(Subnets)' \
    --output text --region "$AWS_REGION" --no-cli-pager

verify_zero 'Internet Gateway' \
  'aws ec2 describe-internet-gateways <project IGW count>' \
  aws ec2 describe-internet-gateways \
    --filters Name=tag:Project,Values="$LAB_PROJECT" \
    --query 'length(InternetGateways)' \
    --output text --region "$AWS_REGION" --no-cli-pager

verify_zero 'VPC' \
  'aws ec2 describe-vpcs <project VPC count>' \
  aws ec2 describe-vpcs \
    --filters Name=tag:Project,Values="$LAB_PROJECT" \
    --query 'length(Vpcs)' \
    --output text --region "$AWS_REGION" --no-cli-pager

log_note "$LAB_AFTER_LOG" 'cleanup_status=PASS; IAM credentials and .env intentionally retained'

printf '\nAWS 서버 리소스 삭제 및 검증 완료\n'
printf '  삭제 전/명령 로그: %s\n' "$LAB_BEFORE_LOG"
printf '  삭제 후 검증 로그: %s\n' "$LAB_AFTER_LOG"
printf '  IAM 사용자와 로컬 .env는 별도로 정리해야 합니다.\n'
