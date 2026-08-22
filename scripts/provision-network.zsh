#!/bin/zsh

set -euo pipefail
set -o pipefail
umask 077

LAB_SCRIPT_DIR="${0:A:h}"
LAB_REPO_ROOT="${LAB_SCRIPT_DIR:h}"
LAB_ENV_FILE="${LAB_REPO_ROOT}/.env"
LAB_LOG_FILE="${LAB_REPO_ROOT}/docs/evidence/logs/02-network-state.log"

set -a
source "$LAB_ENV_FILE"
set +a

: "${AWS_ACCESS_KEY_ID:?AWS_ACCESS_KEY_ID is required}"
: "${AWS_SECRET_ACCESS_KEY:?AWS_SECRET_ACCESS_KEY is required}"
: "${AWS_SESSION_TOKEN:?AWS_SESSION_TOKEN is required}"
: "${AWS_REGION:?AWS_REGION is required}"
: "${LAB_PROJECT:?LAB_PROJECT is required}"
: "${LAB_RESOURCE_PREFIX:?LAB_RESOURCE_PREFIX is required}"
: "${LAB_AZ:?LAB_AZ is required}"
: "${LAB_VPC_CIDR:?LAB_VPC_CIDR is required}"
: "${LAB_SUBNET_CIDR:?LAB_SUBNET_CIDR is required}"

mkdir -p "${LAB_LOG_FILE:h}"

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
    print -r -- "$lab_output"
    printf '[exit=%d]\n' "$lab_status"
  } | tee -a "$LAB_LOG_FILE" >&2

  if (( lab_status != 0 )); then
    return "$lab_status"
  fi

  print -r -- "$lab_output"
}

run_logged() {
  local lab_display="$1"
  shift
  run_capture "$lab_display" "$@" >/dev/null
}

log_note() {
  printf '\n[%s] %s\n[exit=0]\n' \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$1" | tee -a "$LAB_LOG_FILE"
}

persist_env_value() {
  local lab_key="$1"
  local lab_value="$2"
  local lab_tmp_file

  lab_tmp_file="$(mktemp "${LAB_REPO_ROOT}/.env.tmp.XXXXXX")"
  export LAB_PERSIST_KEY="$lab_key"
  export LAB_PERSIST_VALUE="$lab_value"

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
  unset LAB_PERSIST_KEY LAB_PERSIST_VALUE
}

LAB_VPC_NAME="${LAB_RESOURCE_PREFIX}-vpc"
LAB_SUBNET_NAME="${LAB_RESOURCE_PREFIX}-public-subnet"
LAB_IGW_NAME="${LAB_RESOURCE_PREFIX}-igw"
LAB_ROUTE_TABLE_NAME="${LAB_RESOURCE_PREFIX}-public-rt"

LAB_VPC_ID="$(
  aws ec2 describe-vpcs \
    --filters \
      Name=tag:Project,Values="$LAB_PROJECT" \
      Name=tag:Name,Values="$LAB_VPC_NAME" \
    --query 'Vpcs[0].VpcId' \
    --output text \
    --region "$AWS_REGION" \
    --no-cli-pager
)"

if [[ -z "$LAB_VPC_ID" || "$LAB_VPC_ID" == "None" ]]; then
  LAB_VPC_ID="$(run_capture \
    "aws ec2 create-vpc --cidr-block ${LAB_VPC_CIDR} --tag-specifications <Project and Name tags>" \
    aws ec2 create-vpc \
      --cidr-block "$LAB_VPC_CIDR" \
      --tag-specifications \
        "ResourceType=vpc,Tags=[{Key=Name,Value=${LAB_VPC_NAME}},{Key=Project,Value=${LAB_PROJECT}}]" \
      --query 'Vpc.VpcId' \
      --output text \
      --region "$AWS_REGION" \
      --no-cli-pager)"
else
  log_note "reuse VPC: ${LAB_VPC_ID}"
fi

run_logged \
  "aws ec2 modify-vpc-attribute --vpc-id ${LAB_VPC_ID} --enable-dns-support true" \
  aws ec2 modify-vpc-attribute \
    --vpc-id "$LAB_VPC_ID" \
    --enable-dns-support '{"Value":true}' \
    --region "$AWS_REGION" \
    --no-cli-pager

run_logged \
  "aws ec2 modify-vpc-attribute --vpc-id ${LAB_VPC_ID} --enable-dns-hostnames true" \
  aws ec2 modify-vpc-attribute \
    --vpc-id "$LAB_VPC_ID" \
    --enable-dns-hostnames '{"Value":true}' \
    --region "$AWS_REGION" \
    --no-cli-pager

LAB_SUBNET_ID="$(
  aws ec2 describe-subnets \
    --filters \
      Name=vpc-id,Values="$LAB_VPC_ID" \
      Name=tag:Project,Values="$LAB_PROJECT" \
      Name=tag:Name,Values="$LAB_SUBNET_NAME" \
    --query 'Subnets[0].SubnetId' \
    --output text \
    --region "$AWS_REGION" \
    --no-cli-pager
)"

if [[ -z "$LAB_SUBNET_ID" || "$LAB_SUBNET_ID" == "None" ]]; then
  LAB_SUBNET_ID="$(run_capture \
    "aws ec2 create-subnet --vpc-id ${LAB_VPC_ID} --cidr-block ${LAB_SUBNET_CIDR} --availability-zone ${LAB_AZ}" \
    aws ec2 create-subnet \
      --vpc-id "$LAB_VPC_ID" \
      --cidr-block "$LAB_SUBNET_CIDR" \
      --availability-zone "$LAB_AZ" \
      --tag-specifications \
        "ResourceType=subnet,Tags=[{Key=Name,Value=${LAB_SUBNET_NAME}},{Key=Project,Value=${LAB_PROJECT}}]" \
      --query 'Subnet.SubnetId' \
      --output text \
      --region "$AWS_REGION" \
      --no-cli-pager)"
else
  log_note "reuse subnet: ${LAB_SUBNET_ID}"
fi

run_logged \
  "aws ec2 modify-subnet-attribute --subnet-id ${LAB_SUBNET_ID} --map-public-ip-on-launch true" \
  aws ec2 modify-subnet-attribute \
    --subnet-id "$LAB_SUBNET_ID" \
    --map-public-ip-on-launch \
    --region "$AWS_REGION" \
    --no-cli-pager

LAB_IGW_ID="$(
  aws ec2 describe-internet-gateways \
    --filters \
      Name=tag:Project,Values="$LAB_PROJECT" \
      Name=tag:Name,Values="$LAB_IGW_NAME" \
    --query 'InternetGateways[0].InternetGatewayId' \
    --output text \
    --region "$AWS_REGION" \
    --no-cli-pager
)"

if [[ -z "$LAB_IGW_ID" || "$LAB_IGW_ID" == "None" ]]; then
  LAB_IGW_ID="$(run_capture \
    "aws ec2 create-internet-gateway --tag-specifications <Project and Name tags>" \
    aws ec2 create-internet-gateway \
      --tag-specifications \
        "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${LAB_IGW_NAME}},{Key=Project,Value=${LAB_PROJECT}}]" \
      --query 'InternetGateway.InternetGatewayId' \
      --output text \
      --region "$AWS_REGION" \
      --no-cli-pager)"
else
  log_note "reuse internet gateway: ${LAB_IGW_ID}"
fi

LAB_IGW_ATTACHED_VPC="$(
  aws ec2 describe-internet-gateways \
    --internet-gateway-ids "$LAB_IGW_ID" \
    --query 'InternetGateways[0].Attachments[0].VpcId' \
    --output text \
    --region "$AWS_REGION" \
    --no-cli-pager
)"

if [[ "$LAB_IGW_ATTACHED_VPC" != "$LAB_VPC_ID" ]]; then
  run_logged \
    "aws ec2 attach-internet-gateway --internet-gateway-id ${LAB_IGW_ID} --vpc-id ${LAB_VPC_ID}" \
    aws ec2 attach-internet-gateway \
      --internet-gateway-id "$LAB_IGW_ID" \
      --vpc-id "$LAB_VPC_ID" \
      --region "$AWS_REGION" \
      --no-cli-pager
else
  log_note "internet gateway already attached to VPC"
fi

LAB_ROUTE_TABLE_ID="$(
  aws ec2 describe-route-tables \
    --filters \
      Name=vpc-id,Values="$LAB_VPC_ID" \
      Name=tag:Project,Values="$LAB_PROJECT" \
      Name=tag:Name,Values="$LAB_ROUTE_TABLE_NAME" \
    --query 'RouteTables[0].RouteTableId' \
    --output text \
    --region "$AWS_REGION" \
    --no-cli-pager
)"

if [[ -z "$LAB_ROUTE_TABLE_ID" || "$LAB_ROUTE_TABLE_ID" == "None" ]]; then
  LAB_ROUTE_TABLE_ID="$(run_capture \
    "aws ec2 create-route-table --vpc-id ${LAB_VPC_ID}" \
    aws ec2 create-route-table \
      --vpc-id "$LAB_VPC_ID" \
      --tag-specifications \
        "ResourceType=route-table,Tags=[{Key=Name,Value=${LAB_ROUTE_TABLE_NAME}},{Key=Project,Value=${LAB_PROJECT}}]" \
      --query 'RouteTable.RouteTableId' \
      --output text \
      --region "$AWS_REGION" \
      --no-cli-pager)"
else
  log_note "reuse route table: ${LAB_ROUTE_TABLE_ID}"
fi

LAB_DEFAULT_ROUTE_COUNT="$(
  aws ec2 describe-route-tables \
    --route-table-ids "$LAB_ROUTE_TABLE_ID" \
    --query "length(RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0' && GatewayId=='${LAB_IGW_ID}'])" \
    --output text \
    --region "$AWS_REGION" \
    --no-cli-pager
)"

if [[ "$LAB_DEFAULT_ROUTE_COUNT" == "0" ]]; then
  run_logged \
    "aws ec2 create-route --route-table-id ${LAB_ROUTE_TABLE_ID} --destination-cidr-block 0.0.0.0/0 --gateway-id ${LAB_IGW_ID}" \
    aws ec2 create-route \
      --route-table-id "$LAB_ROUTE_TABLE_ID" \
      --destination-cidr-block 0.0.0.0/0 \
      --gateway-id "$LAB_IGW_ID" \
      --region "$AWS_REGION" \
      --no-cli-pager
else
  log_note "default route already exists"
fi

LAB_ROUTE_ASSOCIATION_ID="$(
  aws ec2 describe-route-tables \
    --route-table-ids "$LAB_ROUTE_TABLE_ID" \
    --query "RouteTables[0].Associations[?SubnetId=='${LAB_SUBNET_ID}'].RouteTableAssociationId | [0]" \
    --output text \
    --region "$AWS_REGION" \
    --no-cli-pager
)"

if [[ -z "$LAB_ROUTE_ASSOCIATION_ID" || "$LAB_ROUTE_ASSOCIATION_ID" == "None" ]]; then
  LAB_ROUTE_ASSOCIATION_ID="$(run_capture \
    "aws ec2 associate-route-table --route-table-id ${LAB_ROUTE_TABLE_ID} --subnet-id ${LAB_SUBNET_ID}" \
    aws ec2 associate-route-table \
      --route-table-id "$LAB_ROUTE_TABLE_ID" \
      --subnet-id "$LAB_SUBNET_ID" \
      --query 'AssociationId' \
      --output text \
      --region "$AWS_REGION" \
      --no-cli-pager)"
else
  log_note "route table already associated with subnet"
fi

persist_env_value LAB_VPC_ID "$LAB_VPC_ID"
persist_env_value LAB_SUBNET_ID "$LAB_SUBNET_ID"
persist_env_value LAB_IGW_ID "$LAB_IGW_ID"
persist_env_value LAB_ROUTE_TABLE_ID "$LAB_ROUTE_TABLE_ID"
persist_env_value LAB_ROUTE_ASSOCIATION_ID "$LAB_ROUTE_ASSOCIATION_ID"

run_logged \
  "aws ec2 describe-vpcs --vpc-ids ${LAB_VPC_ID} <limited fields>" \
  aws ec2 describe-vpcs \
    --vpc-ids "$LAB_VPC_ID" \
    --query 'Vpcs[].{VpcId:VpcId,CidrBlock:CidrBlock,State:State,Project:Tags[?Key==`Project`].Value|[0]}' \
    --region "$AWS_REGION" \
    --no-cli-pager

run_logged \
  "aws ec2 describe-subnets --subnet-ids ${LAB_SUBNET_ID} <limited fields>" \
  aws ec2 describe-subnets \
    --subnet-ids "$LAB_SUBNET_ID" \
    --query 'Subnets[].{SubnetId:SubnetId,VpcId:VpcId,CidrBlock:CidrBlock,AvailabilityZone:AvailabilityZone,MapPublicIpOnLaunch:MapPublicIpOnLaunch}' \
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
    --query 'RouteTables[].{RouteTableId:RouteTableId,Routes:Routes[].{Destination:DestinationCidrBlock,GatewayId:GatewayId,State:State},Associations:Associations[].{SubnetId:SubnetId,AssociationId:RouteTableAssociationId}}' \
    --region "$AWS_REGION" \
    --no-cli-pager

printf 'Network provisioning complete.\n'
