#!/usr/bin/env bash

set -euo pipefail
umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"
LOG_DIR="$ROOT_DIR/docs/evidence/logs"
NETWORK_LOG="$LOG_DIR/02-network-state.log"
SG_LOG="$LOG_DIR/03-security-group.log"
EC2_LOG="$LOG_DIR/04-ec2-web-server.log"
SSH_LOG="$LOG_DIR/04-ssh-connection.log"
EXTERNAL_LOG="$LOG_DIR/05-external-health.log"
HTTP_LOG="$LOG_DIR/05-http-200-ok.log"
SECRET_DIR="$ROOT_DIR/.secrets"

# 공통 사전 검사와 AWS EC2 호출 형식을 한곳에서 관리한다.
need() {
  command -v "$1" >/dev/null 2>&1 || { printf '필수 프로그램을 찾을 수 없습니다: %s\n' "$1" >&2; exit 1; }
}

aws_ec2() {
  aws ec2 "$@" --region "$AWS_REGION" --no-cli-pager
}

# 생성된 리소스 ID를 즉시 .env에 저장해 중간 실패 후에도 재실행할 수 있게 한다.
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

# 명령, 출력, 종료 코드를 지정한 증거 로그에 기록한다.
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

is_empty() {
  [[ -z "${1:-}" || "$1" == None ]]
}

# AWS 세션·리전·필수 설정을 검증한 뒤 이번 실행의 로그를 새로 시작한다.
(( $# == 0 )) || { printf '사용법: ./scripts/setup-server.sh\n' >&2; exit 2; }
for command in aws awk curl mktemp ssh tee tr; do need "$command"; done
[[ -f "$ENV_FILE" ]] || { printf '.env가 없습니다. 먼저 ./scripts/setup-aws-cli.sh를 실행하세요.\n' >&2; exit 1; }
chmod 600 "$ENV_FILE"

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

for variable in AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_REGION \
  LAB_PROJECT LAB_RESOURCE_PREFIX LAB_AZ LAB_VPC_CIDR LAB_SUBNET_CIDR LAB_INSTANCE_TYPE LAB_KEY_NAME; do
  [[ -n "${!variable:-}" ]] || { printf '필수 환경 변수가 없습니다: %s\n' "$variable" >&2; exit 1; }
done
[[ "$AWS_REGION" == ap-northeast-2 ]] || { printf '서울 리전(ap-northeast-2)만 사용할 수 있습니다.\n' >&2; exit 1; }

CALLER="$(aws sts get-caller-identity --query "contains(Arn, 'user/lab-cloud-web')" \
  --output text --region "$AWS_REGION" --no-cli-pager)"
case "$CALLER" in True|true) ;; *) printf 'AWS 세션이 만료됐거나 lab-cloud-web 사용자가 아닙니다.\n' >&2; exit 1 ;; esac

mkdir -p "$LOG_DIR" "$SECRET_DIR"
chmod 700 "$SECRET_DIR"
for file in "$NETWORK_LOG" "$SG_LOG" "$EC2_LOG" "$SSH_LOG" "$EXTERNAL_LOG" "$HTTP_LOG"; do
  : > "$file"
  chmod 600 "$file"
done

VPC_NAME="${LAB_RESOURCE_PREFIX}-vpc"
SUBNET_NAME="${LAB_RESOURCE_PREFIX}-public-subnet"
IGW_NAME="${LAB_RESOURCE_PREFIX}-igw"
ROUTE_NAME="${LAB_RESOURCE_PREFIX}-public-rt"
SG_NAME="${LAB_RESOURCE_PREFIX}-sg"
INSTANCE_NAME="${LAB_RESOURCE_PREFIX}-ec2"

# VPC를 태그로 재사용하거나 새로 만들고 DNS 기능을 활성화한다.
LAB_VPC_ID="$(aws_ec2 describe-vpcs \
  --filters "Name=tag:Project,Values=$LAB_PROJECT" "Name=tag:Name,Values=$VPC_NAME" \
  --query 'Vpcs[0].VpcId' --output text)"
if is_empty "$LAB_VPC_ID"; then
  LAB_VPC_ID="$(capture "$NETWORK_LOG" "aws ec2 create-vpc --cidr-block $LAB_VPC_CIDR <Project and Name tags>" \
    aws_ec2 create-vpc --cidr-block "$LAB_VPC_CIDR" \
      --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=$VPC_NAME},{Key=Project,Value=$LAB_PROJECT}]" \
      --query 'Vpc.VpcId' --output text)"
  set_env LAB_VPC_ID "$LAB_VPC_ID"
  logged "$NETWORK_LOG" "aws ec2 wait vpc-available --vpc-ids $LAB_VPC_ID" aws_ec2 wait vpc-available --vpc-ids "$LAB_VPC_ID"
else
  note "$NETWORK_LOG" "reuse VPC: $LAB_VPC_ID"
  set_env LAB_VPC_ID "$LAB_VPC_ID"
fi
logged "$NETWORK_LOG" "aws ec2 modify-vpc-attribute --vpc-id $LAB_VPC_ID --enable-dns-support true" \
  aws_ec2 modify-vpc-attribute --vpc-id "$LAB_VPC_ID" --enable-dns-support '{"Value":true}'
logged "$NETWORK_LOG" "aws ec2 modify-vpc-attribute --vpc-id $LAB_VPC_ID --enable-dns-hostnames true" \
  aws_ec2 modify-vpc-attribute --vpc-id "$LAB_VPC_ID" --enable-dns-hostnames '{"Value":true}'

# Public Subnet을 구성하고 인스턴스 Public IPv4 자동 할당을 활성화한다.
LAB_SUBNET_ID="$(aws_ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$LAB_VPC_ID" "Name=tag:Project,Values=$LAB_PROJECT" "Name=tag:Name,Values=$SUBNET_NAME" \
  --query 'Subnets[0].SubnetId' --output text)"
if is_empty "$LAB_SUBNET_ID"; then
  LAB_SUBNET_ID="$(capture "$NETWORK_LOG" "aws ec2 create-subnet --vpc-id $LAB_VPC_ID --cidr-block $LAB_SUBNET_CIDR --availability-zone $LAB_AZ" \
    aws_ec2 create-subnet --vpc-id "$LAB_VPC_ID" --cidr-block "$LAB_SUBNET_CIDR" --availability-zone "$LAB_AZ" \
      --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$SUBNET_NAME},{Key=Project,Value=$LAB_PROJECT}]" \
      --query 'Subnet.SubnetId' --output text)"
else
  note "$NETWORK_LOG" "reuse subnet: $LAB_SUBNET_ID"
fi
set_env LAB_SUBNET_ID "$LAB_SUBNET_ID"
logged "$NETWORK_LOG" "aws ec2 modify-subnet-attribute --subnet-id $LAB_SUBNET_ID --map-public-ip-on-launch true" \
  aws_ec2 modify-subnet-attribute --subnet-id "$LAB_SUBNET_ID" --map-public-ip-on-launch

# Internet Gateway를 구성하고 현재 VPC에 연결한다.
LAB_IGW_ID="$(aws_ec2 describe-internet-gateways \
  --filters "Name=tag:Project,Values=$LAB_PROJECT" "Name=tag:Name,Values=$IGW_NAME" \
  --query 'InternetGateways[0].InternetGatewayId' --output text)"
if is_empty "$LAB_IGW_ID"; then
  LAB_IGW_ID="$(capture "$NETWORK_LOG" 'aws ec2 create-internet-gateway <Project and Name tags>' \
    aws_ec2 create-internet-gateway \
      --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=$IGW_NAME},{Key=Project,Value=$LAB_PROJECT}]" \
      --query 'InternetGateway.InternetGatewayId' --output text)"
else
  note "$NETWORK_LOG" "reuse internet gateway: $LAB_IGW_ID"
fi
set_env LAB_IGW_ID "$LAB_IGW_ID"
ATTACHED_VPC="$(aws_ec2 describe-internet-gateways --internet-gateway-ids "$LAB_IGW_ID" \
  --query 'InternetGateways[0].Attachments[0].VpcId' --output text)"
if is_empty "$ATTACHED_VPC"; then
  logged "$NETWORK_LOG" "aws ec2 attach-internet-gateway --internet-gateway-id $LAB_IGW_ID --vpc-id $LAB_VPC_ID" \
    aws_ec2 attach-internet-gateway --internet-gateway-id "$LAB_IGW_ID" --vpc-id "$LAB_VPC_ID"
elif [[ "$ATTACHED_VPC" != "$LAB_VPC_ID" ]]; then
  printf 'Internet Gateway가 다른 VPC에 연결되어 있습니다: %s\n' "$ATTACHED_VPC" >&2
  exit 1
fi

# 사용자 Route Table에 기본 인터넷 경로를 만들고 Public Subnet과 연결한다.
LAB_ROUTE_TABLE_ID="$(aws_ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=$LAB_VPC_ID" "Name=tag:Project,Values=$LAB_PROJECT" "Name=tag:Name,Values=$ROUTE_NAME" \
  --query 'RouteTables[0].RouteTableId' --output text)"
if is_empty "$LAB_ROUTE_TABLE_ID"; then
  LAB_ROUTE_TABLE_ID="$(capture "$NETWORK_LOG" "aws ec2 create-route-table --vpc-id $LAB_VPC_ID" \
    aws_ec2 create-route-table --vpc-id "$LAB_VPC_ID" \
      --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=$ROUTE_NAME},{Key=Project,Value=$LAB_PROJECT}]" \
      --query 'RouteTable.RouteTableId' --output text)"
else
  note "$NETWORK_LOG" "reuse route table: $LAB_ROUTE_TABLE_ID"
fi
set_env LAB_ROUTE_TABLE_ID "$LAB_ROUTE_TABLE_ID"
ROUTE_TARGET="$(aws_ec2 describe-route-tables --route-table-ids "$LAB_ROUTE_TABLE_ID" \
  --query "RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0'].GatewayId | [0]" --output text)"
if is_empty "$ROUTE_TARGET"; then
  logged "$NETWORK_LOG" "aws ec2 create-route --route-table-id $LAB_ROUTE_TABLE_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $LAB_IGW_ID" \
    aws_ec2 create-route --route-table-id "$LAB_ROUTE_TABLE_ID" --destination-cidr-block 0.0.0.0/0 --gateway-id "$LAB_IGW_ID"
elif [[ "$ROUTE_TARGET" != "$LAB_IGW_ID" ]]; then
  printf '기본 경로가 다른 대상으로 설정되어 있습니다: %s\n' "$ROUTE_TARGET" >&2
  exit 1
fi

LAB_ROUTE_ASSOCIATION_ID="$(aws_ec2 describe-route-tables --route-table-ids "$LAB_ROUTE_TABLE_ID" \
  --query "RouteTables[0].Associations[?SubnetId=='$LAB_SUBNET_ID'].RouteTableAssociationId | [0]" --output text)"
if is_empty "$LAB_ROUTE_ASSOCIATION_ID"; then
  LAB_ROUTE_ASSOCIATION_ID="$(capture "$NETWORK_LOG" "aws ec2 associate-route-table --route-table-id $LAB_ROUTE_TABLE_ID --subnet-id $LAB_SUBNET_ID" \
    aws_ec2 associate-route-table --route-table-id "$LAB_ROUTE_TABLE_ID" --subnet-id "$LAB_SUBNET_ID" \
      --query 'AssociationId' --output text)"
fi
set_env LAB_ROUTE_ASSOCIATION_ID "$LAB_ROUTE_ASSOCIATION_ID"

# 생성 직후 네트워크 네 요소의 실제 상태를 제한된 필드로 기록한다.
logged "$NETWORK_LOG" "aws ec2 describe-vpcs --vpc-ids $LAB_VPC_ID <limited fields>" \
  aws_ec2 describe-vpcs --vpc-ids "$LAB_VPC_ID" \
    --query 'Vpcs[].{VpcId:VpcId,Cidr:CidrBlock,State:State,Project:Tags[?Key==`Project`].Value|[0]}'
logged "$NETWORK_LOG" "aws ec2 describe-subnets --subnet-ids $LAB_SUBNET_ID <public subnet fields>" \
  aws_ec2 describe-subnets --subnet-ids "$LAB_SUBNET_ID" \
    --query 'Subnets[].{SubnetId:SubnetId,VpcId:VpcId,Cidr:CidrBlock,AZ:AvailabilityZone,PublicIpAutoAssign:MapPublicIpOnLaunch}'
logged "$NETWORK_LOG" "aws ec2 describe-internet-gateways --internet-gateway-ids $LAB_IGW_ID <attachments>" \
  aws_ec2 describe-internet-gateways --internet-gateway-ids "$LAB_IGW_ID" \
    --query 'InternetGateways[].{InternetGatewayId:InternetGatewayId,Attachments:Attachments}'
logged "$NETWORK_LOG" "aws ec2 describe-route-tables --route-table-ids $LAB_ROUTE_TABLE_ID <routes and associations>" \
  aws_ec2 describe-route-tables --route-table-ids "$LAB_ROUTE_TABLE_ID" \
    --query 'RouteTables[].{RouteTableId:RouteTableId,Routes:Routes,Associations:Associations}'

# 현재 학습자 공인 IP를 조회해 SSH 허용 대역을 정확한 /32로 고정한다.
PUBLIC_CLIENT_IP="$(curl -4 --fail --silent --show-error https://checkip.amazonaws.com | tr -d '[:space:]')"
[[ "$PUBLIC_CLIENT_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || { printf '공인 IPv4를 확인하지 못했습니다.\n' >&2; exit 1; }
LAB_LEARNER_IP_CIDR="${PUBLIC_CLIENT_IP}/32"
set_env LAB_LEARNER_IP_CIDR "$LAB_LEARNER_IP_CIDR"

LAB_SECURITY_GROUP_ID="$(aws_ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=$LAB_VPC_ID" "Name=tag:Project,Values=$LAB_PROJECT" "Name=group-name,Values=$SG_NAME" \
  --query 'SecurityGroups[0].GroupId' --output text)"
if is_empty "$LAB_SECURITY_GROUP_ID"; then
  LAB_SECURITY_GROUP_ID="$(capture "$SG_LOG" "aws ec2 create-security-group --group-name $SG_NAME --vpc-id $LAB_VPC_ID" \
    aws_ec2 create-security-group --group-name "$SG_NAME" \
      --description 'HTTP public and SSH learner IP for codyssey-06-1' --vpc-id "$LAB_VPC_ID" \
      --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=$SG_NAME},{Key=Project,Value=$LAB_PROJECT}]" \
      --query 'GroupId' --output text)"
else
  note "$SG_LOG" "reuse security group: $LAB_SECURITY_GROUP_ID"
fi
set_env LAB_SECURITY_GROUP_ID "$LAB_SECURITY_GROUP_ID"

# 예상한 HTTP·SSH 규칙만 남기고, 이전 IP나 불필요한 인바운드 규칙은 제거한다.
HAS_HTTP=false
HAS_SSH=false
while read -r rule_id protocol from_port to_port cidr; do
  [[ -n "$rule_id" && "$rule_id" != None ]] || continue
  if [[ "$protocol" == tcp && "$from_port" == 80 && "$to_port" == 80 && "$cidr" == 0.0.0.0/0 ]]; then
    HAS_HTTP=true
  elif [[ "$protocol" == tcp && "$from_port" == 22 && "$to_port" == 22 && "$cidr" == "$LAB_LEARNER_IP_CIDR" ]]; then
    HAS_SSH=true
  else
    logged "$SG_LOG" "aws ec2 revoke-security-group-ingress --group-id $LAB_SECURITY_GROUP_ID --security-group-rule-ids $rule_id <unexpected inbound rule>" \
      aws_ec2 revoke-security-group-ingress --group-id "$LAB_SECURITY_GROUP_ID" --security-group-rule-ids "$rule_id"
  fi
done < <(aws_ec2 describe-security-group-rules \
  --filters "Name=group-id,Values=$LAB_SECURITY_GROUP_ID" \
  --query 'SecurityGroupRules[?IsEgress==`false`].[SecurityGroupRuleId,IpProtocol,FromPort,ToPort,CidrIpv4]' \
  --output text)

if [[ "$HAS_HTTP" != true ]]; then
  logged "$SG_LOG" "aws ec2 authorize-security-group-ingress --group-id $LAB_SECURITY_GROUP_ID --protocol tcp --port 80 --cidr 0.0.0.0/0" \
    aws_ec2 authorize-security-group-ingress --group-id "$LAB_SECURITY_GROUP_ID" --protocol tcp --port 80 --cidr 0.0.0.0/0
fi
if [[ "$HAS_SSH" != true ]]; then
  logged "$SG_LOG" "aws ec2 authorize-security-group-ingress --group-id $LAB_SECURITY_GROUP_ID --protocol tcp --port 22 --cidr <learner-ip>/32" \
    aws_ec2 authorize-security-group-ingress --group-id "$LAB_SECURITY_GROUP_ID" --protocol tcp --port 22 --cidr "$LAB_LEARNER_IP_CIDR"
fi
logged "$SG_LOG" "aws ec2 describe-security-groups --group-ids $LAB_SECURITY_GROUP_ID <inbound rules>" \
  aws_ec2 describe-security-groups --group-ids "$LAB_SECURITY_GROUP_ID" \
    --query 'SecurityGroups[].{GroupId:GroupId,Inbound:IpPermissions[].{Protocol:IpProtocol,FromPort:FromPort,ToPort:ToPort,CIDRs:IpRanges[].CidrIp}}'

# AWS Key Pair와 로컬 Private Key가 함께 존재할 때만 재사용한다.
PRIVATE_KEY="$SECRET_DIR/${LAB_KEY_NAME}.pem"
KEY_EXISTS="$(aws_ec2 describe-key-pairs --key-names "$LAB_KEY_NAME" --query 'length(KeyPairs)' --output text 2>/dev/null || printf '0')"
if [[ "$KEY_EXISTS" == 0 ]]; then
  [[ ! -e "$PRIVATE_KEY" ]] || { printf '로컬 키만 남아 있습니다. cleanup-server.sh로 정리한 뒤 다시 실행하세요: %s\n' "$PRIVATE_KEY" >&2; exit 1; }
  KEY_MATERIAL="$(aws_ec2 create-key-pair --key-name "$LAB_KEY_NAME" --key-type ed25519 --key-format pem \
    --tag-specifications "ResourceType=key-pair,Tags=[{Key=Name,Value=$LAB_KEY_NAME},{Key=Project,Value=$LAB_PROJECT}]" \
    --query 'KeyMaterial' --output text)"
  printf '%s\n' "$KEY_MATERIAL" > "$PRIVATE_KEY"
  chmod 600 "$PRIVATE_KEY"
  unset KEY_MATERIAL
  note "$EC2_LOG" "aws ec2 create-key-pair --key-name $LAB_KEY_NAME --key-type ed25519 <private key stored locally and redacted>"
elif [[ ! -f "$PRIVATE_KEY" ]]; then
  printf 'AWS Key Pair의 로컬 Private Key가 없습니다: %s\n' "$PRIVATE_KEY" >&2
  exit 1
else
  note "$EC2_LOG" "reuse key pair and protected local private key"
fi

# 최신 Amazon Linux 2023 AMI를 선택하고 EC2를 생성하거나 기존 인스턴스를 재사용한다.
LAB_AMI_ID="$(aws_ec2 describe-images --owners amazon \
  --filters 'Name=name,Values=al2023-ami-2023.*-kernel-6.1-x86_64' 'Name=architecture,Values=x86_64' \
    'Name=root-device-type,Values=ebs' 'Name=state,Values=available' \
  --query 'sort_by(Images,&CreationDate)[-1].ImageId' --output text)"
is_empty "$LAB_AMI_ID" && { printf 'Amazon Linux 2023 AMI를 찾지 못했습니다.\n' >&2; exit 1; }
set_env LAB_AMI_ID "$LAB_AMI_ID"

LAB_INSTANCE_ID="$(aws_ec2 describe-instances \
  --filters "Name=tag:Project,Values=$LAB_PROJECT" "Name=tag:Name,Values=$INSTANCE_NAME" \
    'Name=instance-state-name,Values=pending,running,stopping,stopped' \
  --query 'Reservations[].Instances[] | [0].InstanceId' --output text)"
if is_empty "$LAB_INSTANCE_ID"; then
  LAB_INSTANCE_ID="$(capture "$EC2_LOG" "aws ec2 run-instances --image-id $LAB_AMI_ID --instance-type $LAB_INSTANCE_TYPE <network, key, 8GiB gp3, user-data>" \
    aws_ec2 run-instances --image-id "$LAB_AMI_ID" --instance-type "$LAB_INSTANCE_TYPE" --count 1 \
      --subnet-id "$LAB_SUBNET_ID" --security-group-ids "$LAB_SECURITY_GROUP_ID" --key-name "$LAB_KEY_NAME" \
      --associate-public-ip-address \
      --block-device-mappings 'DeviceName=/dev/xvda,Ebs={VolumeSize=8,VolumeType=gp3,DeleteOnTermination=true,Encrypted=true}' \
      --user-data "file://$ROOT_DIR/infra/user-data.sh" \
      --tag-specifications \
        "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME},{Key=Project,Value=$LAB_PROJECT}]" \
        "ResourceType=volume,Tags=[{Key=Name,Value=${LAB_RESOURCE_PREFIX}-root-volume},{Key=Project,Value=$LAB_PROJECT}]" \
      --query 'Instances[0].InstanceId' --output text)"
else
  note "$EC2_LOG" "reuse EC2 instance: $LAB_INSTANCE_ID"
fi
set_env LAB_INSTANCE_ID "$LAB_INSTANCE_ID"

INSTANCE_STATE="$(aws_ec2 describe-instances --instance-ids "$LAB_INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].State.Name' --output text)"
if [[ "$INSTANCE_STATE" == stopping ]]; then
  logged "$EC2_LOG" "aws ec2 wait instance-stopped --instance-ids $LAB_INSTANCE_ID" aws_ec2 wait instance-stopped --instance-ids "$LAB_INSTANCE_ID"
  INSTANCE_STATE=stopped
fi
if [[ "$INSTANCE_STATE" == stopped ]]; then
  logged "$EC2_LOG" "aws ec2 start-instances --instance-ids $LAB_INSTANCE_ID" aws_ec2 start-instances --instance-ids "$LAB_INSTANCE_ID"
fi
logged "$EC2_LOG" "aws ec2 wait instance-running --instance-ids $LAB_INSTANCE_ID" aws_ec2 wait instance-running --instance-ids "$LAB_INSTANCE_ID"
logged "$EC2_LOG" "aws ec2 wait instance-status-ok --instance-ids $LAB_INSTANCE_ID" aws_ec2 wait instance-status-ok --instance-ids "$LAB_INSTANCE_ID"

LAB_PUBLIC_IP="$(aws_ec2 describe-instances --instance-ids "$LAB_INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)"
LAB_VOLUME_ID="$(aws_ec2 describe-instances --instance-ids "$LAB_INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].BlockDeviceMappings[0].Ebs.VolumeId' --output text)"
is_empty "$LAB_PUBLIC_IP" && { printf 'EC2에 Public IPv4가 없습니다.\n' >&2; exit 1; }
set_env LAB_PUBLIC_IP "$LAB_PUBLIC_IP"
set_env LAB_VOLUME_ID "$LAB_VOLUME_ID"

logged "$EC2_LOG" "aws ec2 describe-instances --instance-ids $LAB_INSTANCE_ID <limited fields>" \
  aws_ec2 describe-instances --instance-ids "$LAB_INSTANCE_ID" \
    --query 'Reservations[].Instances[].{InstanceId:InstanceId,State:State.Name,InstanceType:InstanceType,VpcId:VpcId,SubnetId:SubnetId,PublicIpAddress:PublicIpAddress,SecurityGroups:SecurityGroups,BlockDevices:BlockDeviceMappings}'
logged "$EC2_LOG" "aws ec2 describe-volumes --volume-ids $LAB_VOLUME_ID <size, type, encryption, state>" \
  aws_ec2 describe-volumes --volume-ids "$LAB_VOLUME_ID" \
    --query 'Volumes[].{VolumeId:VolumeId,SizeGiB:Size,VolumeType:VolumeType,Encrypted:Encrypted,State:State}'

# user-data가 Nginx와 /health를 준비할 때까지 외부 요청을 재시도한다.
HTTP_READY=false
for (( attempt=1; attempt<=36; attempt++ )); do
  if body="$(curl --fail --silent --connect-timeout 3 --max-time 5 "http://$LAB_PUBLIC_IP/health" 2>/dev/null)" && [[ "$body" == OK ]]; then
    HTTP_READY=true
    break
  fi
  sleep 10
done
[[ "$HTTP_READY" == true ]] || { printf '외부 /health가 제한 시간 안에 준비되지 않았습니다.\n' >&2; exit 1; }

# SSH 접속과 인스턴스 내부 Nginx·localhost·아웃바운드 상태를 검증한다.
logged "$SSH_LOG" \
  "ssh -i <protected-key> -o BatchMode=yes -o ConnectTimeout=10 ec2-user@$LAB_PUBLIC_IP <connection proof>" \
  ssh -i "$PRIVATE_KEY" -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
    -o "UserKnownHostsFile=$SECRET_DIR/known_hosts" "ec2-user@$LAB_PUBLIC_IP" \
    "printf 'ssh_connection=PASS\\nremote_user='; id -un; printf 'remote_host='; hostname"

logged "$EC2_LOG" "ssh -i <protected-key> ec2-user@$LAB_PUBLIC_IP <nginx, localhost, outbound checks>" \
  ssh -i "$PRIVATE_KEY" -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
    -o "UserKnownHostsFile=$SECRET_DIR/known_hosts" "ec2-user@$LAB_PUBLIC_IP" \
    "printf 'nginx='; systemctl is-active nginx; printf 'localhost-root-status='; curl -s -o /dev/null -w '%{http_code}\\n' http://localhost/; printf 'localhost-health-status='; curl -s -o /dev/null -w '%{http_code}\\n' http://localhost/health; printf 'localhost-health-body='; curl -fsS http://localhost/health; printf '\\noutbound='; curl -fsS https://example.com/ >/dev/null && printf 'success\\n'"

# 최종 외부 /health의 상태 코드와 본문을 두 제출용 로그에 동일하게 기록한다.
BODY_FILE="$(mktemp)"
set +e
HTTP_STATUS="$(curl --silent --show-error --connect-timeout 5 --max-time 15 \
  --output "$BODY_FILE" --write-out '%{http_code}' "http://$LAB_PUBLIC_IP/health")"
CURL_STATUS=$?
set -e
HTTP_BODY="$(<"$BODY_FILE")"
rm -f "$BODY_FILE"
RESULT=FAIL
[[ "$CURL_STATUS" == 0 && "$HTTP_STATUS" == 200 && "$HTTP_BODY" == OK ]] && RESULT=PASS
for file in "$EXTERNAL_LOG" "$HTTP_LOG"; do
  {
    printf '\n[%s] $ curl http://%s/health <expect HTTP 200 and body OK>\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$LAB_PUBLIC_IP"
    printf 'http_status=%s\nresponse_body=%s\nhttp_200_ok=%s\n[exit=%d]\n' "$HTTP_STATUS" "$HTTP_BODY" "$RESULT" "$CURL_STATUS"
  } | tee -a "$file"
done
[[ "$RESULT" == PASS ]] || { printf '외부 HTTP 검증에 실패했습니다.\n' >&2; exit 1; }

printf '\n서버 설정 완료\n  웹 페이지: http://%s/\n  상태 확인: http://%s/health\n  로그: %s\n' \
  "$LAB_PUBLIC_IP" "$LAB_PUBLIC_IP" "$LOG_DIR"
