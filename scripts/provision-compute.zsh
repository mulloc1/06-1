#!/bin/zsh

set -euo pipefail
set -o pipefail
umask 077

LAB_SCRIPT_DIR="${0:A:h}"
LAB_REPO_ROOT="${LAB_SCRIPT_DIR:h}"
LAB_ENV_FILE="${LAB_REPO_ROOT}/.env"
LAB_SG_LOG="${LAB_REPO_ROOT}/docs/evidence/logs/03-security-group.log"
LAB_EC2_LOG="${LAB_REPO_ROOT}/docs/evidence/logs/04-ec2-web-server.log"
LAB_SSH_LOG="${LAB_REPO_ROOT}/docs/evidence/logs/04-ssh-connection.log"
LAB_EXTERNAL_LOG="${LAB_REPO_ROOT}/docs/evidence/logs/05-external-health.log"
LAB_HTTP_200_LOG="${LAB_REPO_ROOT}/docs/evidence/logs/05-http-200-ok.log"
LAB_SECRET_DIR="${LAB_REPO_ROOT}/.secrets"

set -a
source "$LAB_ENV_FILE"
set +a

: "${AWS_ACCESS_KEY_ID:?AWS_ACCESS_KEY_ID is required}"
: "${AWS_SECRET_ACCESS_KEY:?AWS_SECRET_ACCESS_KEY is required}"
: "${AWS_SESSION_TOKEN:?AWS_SESSION_TOKEN is required}"
: "${AWS_REGION:?AWS_REGION is required}"
: "${LAB_PROJECT:?LAB_PROJECT is required}"
: "${LAB_RESOURCE_PREFIX:?LAB_RESOURCE_PREFIX is required}"
: "${LAB_VPC_ID:?LAB_VPC_ID is required}"
: "${LAB_SUBNET_ID:?LAB_SUBNET_ID is required}"
: "${LAB_INSTANCE_TYPE:?LAB_INSTANCE_TYPE is required}"
: "${LAB_KEY_NAME:?LAB_KEY_NAME is required}"

mkdir -p "${LAB_SG_LOG:h}" "$LAB_SECRET_DIR"
chmod 700 "$LAB_SECRET_DIR"

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

if [[ -z "${LAB_LEARNER_IP_CIDR:-}" ]]; then
  LAB_PUBLIC_CLIENT_IP="$(curl -4 --fail --silent --show-error https://checkip.amazonaws.com | tr -d '[:space:]')"
  if ! [[ "$LAB_PUBLIC_CLIENT_IP" =~ '^([0-9]{1,3}\.){3}[0-9]{1,3}$' ]]; then
    printf 'Unable to determine a valid public IPv4 address.\n' >&2
    exit 1
  fi
  LAB_LEARNER_IP_CIDR="${LAB_PUBLIC_CLIENT_IP}/32"
  persist_env_value LAB_LEARNER_IP_CIDR "$LAB_LEARNER_IP_CIDR"
  unset LAB_PUBLIC_CLIENT_IP
fi

LAB_SECURITY_GROUP_NAME="${LAB_RESOURCE_PREFIX}-sg"
LAB_SECURITY_GROUP_ID="$(
  aws ec2 describe-security-groups \
    --filters \
      Name=vpc-id,Values="$LAB_VPC_ID" \
      Name=tag:Project,Values="$LAB_PROJECT" \
      Name=group-name,Values="$LAB_SECURITY_GROUP_NAME" \
    --query 'SecurityGroups[0].GroupId' \
    --output text \
    --region "$AWS_REGION" \
    --no-cli-pager
)"

if [[ -z "$LAB_SECURITY_GROUP_ID" || "$LAB_SECURITY_GROUP_ID" == "None" ]]; then
  LAB_SECURITY_GROUP_ID="$(run_capture \
    "$LAB_SG_LOG" \
    "aws ec2 create-security-group --group-name ${LAB_SECURITY_GROUP_NAME} --vpc-id ${LAB_VPC_ID}" \
    aws ec2 create-security-group \
      --group-name "$LAB_SECURITY_GROUP_NAME" \
      --description "HTTP public and SSH learner IP for codyssey-06-1" \
      --vpc-id "$LAB_VPC_ID" \
      --tag-specifications \
        "ResourceType=security-group,Tags=[{Key=Name,Value=${LAB_SECURITY_GROUP_NAME}},{Key=Project,Value=${LAB_PROJECT}}]" \
      --query 'GroupId' \
      --output text \
      --region "$AWS_REGION" \
      --no-cli-pager)"
else
  log_note "$LAB_SG_LOG" "reuse security group: ${LAB_SECURITY_GROUP_ID}"
fi

LAB_SG_JSON="$(
  aws ec2 describe-security-groups \
    --group-ids "$LAB_SECURITY_GROUP_ID" \
    --output json \
    --region "$AWS_REGION" \
    --no-cli-pager
)"

LAB_HTTP_RULE_COUNT="$(
  print -r -- "$LAB_SG_JSON" | jq \
    '[.SecurityGroups[0].IpPermissions[] | select(.IpProtocol == "tcp" and .FromPort == 80 and .ToPort == 80) | .IpRanges[] | select(.CidrIp == "0.0.0.0/0")] | length'
)"

if [[ "$LAB_HTTP_RULE_COUNT" == "0" ]]; then
  run_logged \
    "$LAB_SG_LOG" \
    "aws ec2 authorize-security-group-ingress --group-id ${LAB_SECURITY_GROUP_ID} --protocol tcp --port 80 --cidr 0.0.0.0/0" \
    aws ec2 authorize-security-group-ingress \
      --group-id "$LAB_SECURITY_GROUP_ID" \
      --protocol tcp \
      --port 80 \
      --cidr 0.0.0.0/0 \
      --region "$AWS_REGION" \
      --no-cli-pager
else
  log_note "$LAB_SG_LOG" "HTTP 80 rule already exists"
fi

LAB_SG_JSON="$(
  aws ec2 describe-security-groups \
    --group-ids "$LAB_SECURITY_GROUP_ID" \
    --output json \
    --region "$AWS_REGION" \
    --no-cli-pager
)"

LAB_SSH_RULE_COUNT="$(
  print -r -- "$LAB_SG_JSON" | jq --arg learner_cidr "$LAB_LEARNER_IP_CIDR" \
    '[.SecurityGroups[0].IpPermissions[] | select(.IpProtocol == "tcp" and .FromPort == 22 and .ToPort == 22) | .IpRanges[] | select(.CidrIp == $learner_cidr)] | length'
)"

if [[ "$LAB_SSH_RULE_COUNT" == "0" ]]; then
  run_logged \
    "$LAB_SG_LOG" \
    "aws ec2 authorize-security-group-ingress --group-id ${LAB_SECURITY_GROUP_ID} --protocol tcp --port 22 --cidr <learner-ip>/32" \
    aws ec2 authorize-security-group-ingress \
      --group-id "$LAB_SECURITY_GROUP_ID" \
      --protocol tcp \
      --port 22 \
      --cidr "$LAB_LEARNER_IP_CIDR" \
      --region "$AWS_REGION" \
      --no-cli-pager
else
  log_note "$LAB_SG_LOG" "SSH 22 learner /32 rule already exists"
fi

persist_env_value LAB_SECURITY_GROUP_ID "$LAB_SECURITY_GROUP_ID"

run_logged \
  "$LAB_SG_LOG" \
  "aws ec2 describe-security-groups --group-ids ${LAB_SECURITY_GROUP_ID} <inbound rules>" \
  aws ec2 describe-security-groups \
    --group-ids "$LAB_SECURITY_GROUP_ID" \
    --query 'SecurityGroups[].{GroupId:GroupId,GroupName:GroupName,Inbound:IpPermissions[].{Protocol:IpProtocol,FromPort:FromPort,ToPort:ToPort,CIDRs:IpRanges[].CidrIp}}' \
    --region "$AWS_REGION" \
    --no-cli-pager

LAB_PRIVATE_KEY_PATH="${LAB_SECRET_DIR}/${LAB_KEY_NAME}.pem"
LAB_KEY_EXISTS="$(
  aws ec2 describe-key-pairs \
    --key-names "$LAB_KEY_NAME" \
    --query 'length(KeyPairs)' \
    --output text \
    --region "$AWS_REGION" \
    --no-cli-pager \
    2>/dev/null || printf '0'
)"

if [[ "$LAB_KEY_EXISTS" == "0" ]]; then
  if [[ -e "$LAB_PRIVATE_KEY_PATH" ]]; then
    printf 'Local key exists but AWS key pair does not: %s\n' "$LAB_PRIVATE_KEY_PATH" >&2
    exit 1
  fi

  LAB_KEY_MATERIAL="$(
    aws ec2 create-key-pair \
      --key-name "$LAB_KEY_NAME" \
      --key-type ed25519 \
      --key-format pem \
      --tag-specifications \
        "ResourceType=key-pair,Tags=[{Key=Name,Value=${LAB_KEY_NAME}},{Key=Project,Value=${LAB_PROJECT}}]" \
      --query 'KeyMaterial' \
      --output text \
      --region "$AWS_REGION" \
      --no-cli-pager
  )"

  print -r -- "$LAB_KEY_MATERIAL" | tee "$LAB_PRIVATE_KEY_PATH" >/dev/null
  chmod 600 "$LAB_PRIVATE_KEY_PATH"
  unset LAB_KEY_MATERIAL
  log_note "$LAB_EC2_LOG" "aws ec2 create-key-pair --key-name ${LAB_KEY_NAME} --key-type ed25519 (private key output stored locally and redacted)"
elif [[ ! -f "$LAB_PRIVATE_KEY_PATH" ]]; then
  printf 'AWS key pair exists but its local private key is unavailable: %s\n' "$LAB_PRIVATE_KEY_PATH" >&2
  exit 1
else
  log_note "$LAB_EC2_LOG" "reuse key pair and protected local private key"
fi

run_logged \
  "$LAB_EC2_LOG" \
  "aws ec2 describe-key-pairs --key-names ${LAB_KEY_NAME} <metadata only>" \
  aws ec2 describe-key-pairs \
    --key-names "$LAB_KEY_NAME" \
    --query 'KeyPairs[].{KeyName:KeyName,KeyType:KeyType,Project:Tags[?Key==`Project`].Value|[0]}' \
    --region "$AWS_REGION" \
    --no-cli-pager

LAB_AMI_ID="$(
  aws ec2 describe-images \
    --owners amazon \
    --filters \
      'Name=name,Values=al2023-ami-2023.*-kernel-6.1-x86_64' \
      'Name=architecture,Values=x86_64' \
      'Name=root-device-type,Values=ebs' \
      'Name=state,Values=available' \
    --query 'sort_by(Images,&CreationDate)[-1].ImageId' \
    --output text \
    --region "$AWS_REGION" \
    --no-cli-pager
)"

if [[ -z "$LAB_AMI_ID" || "$LAB_AMI_ID" == "None" ]]; then
  printf 'No matching Amazon Linux 2023 AMI found.\n' >&2
  exit 1
fi
persist_env_value LAB_AMI_ID "$LAB_AMI_ID"

LAB_INSTANCE_ID="$(
  aws ec2 describe-instances \
    --filters \
      Name=tag:Project,Values="$LAB_PROJECT" \
      Name=tag:Name,Values="${LAB_RESOURCE_PREFIX}-ec2" \
      Name=instance-state-name,Values=pending,running,stopping,stopped \
    --query 'Reservations[].Instances[] | [0].InstanceId' \
    --output text \
    --region "$AWS_REGION" \
    --no-cli-pager
)"

if [[ -z "$LAB_INSTANCE_ID" || "$LAB_INSTANCE_ID" == "None" ]]; then
  LAB_INSTANCE_ID="$(run_capture \
    "$LAB_EC2_LOG" \
    "aws ec2 run-instances --image-id ${LAB_AMI_ID} --instance-type ${LAB_INSTANCE_TYPE} --subnet-id ${LAB_SUBNET_ID} --security-group-ids ${LAB_SECURITY_GROUP_ID} --key-name ${LAB_KEY_NAME} --user-data infra/user-data.sh --8GiB-gp3" \
    aws ec2 run-instances \
      --image-id "$LAB_AMI_ID" \
      --instance-type "$LAB_INSTANCE_TYPE" \
      --count 1 \
      --subnet-id "$LAB_SUBNET_ID" \
      --security-group-ids "$LAB_SECURITY_GROUP_ID" \
      --key-name "$LAB_KEY_NAME" \
      --associate-public-ip-address \
      --block-device-mappings \
        'DeviceName=/dev/xvda,Ebs={VolumeSize=8,VolumeType=gp3,DeleteOnTermination=true,Encrypted=true}' \
      --user-data "file://${LAB_REPO_ROOT}/infra/user-data.sh" \
      --tag-specifications \
        "ResourceType=instance,Tags=[{Key=Name,Value=${LAB_RESOURCE_PREFIX}-ec2},{Key=Project,Value=${LAB_PROJECT}}]" \
        "ResourceType=volume,Tags=[{Key=Name,Value=${LAB_RESOURCE_PREFIX}-root-volume},{Key=Project,Value=${LAB_PROJECT}}]" \
      --query 'Instances[0].InstanceId' \
      --output text \
      --region "$AWS_REGION" \
      --no-cli-pager)"
else
  log_note "$LAB_EC2_LOG" "reuse EC2 instance: ${LAB_INSTANCE_ID}"
fi

persist_env_value LAB_INSTANCE_ID "$LAB_INSTANCE_ID"

run_logged \
  "$LAB_EC2_LOG" \
  "aws ec2 wait instance-running --instance-ids ${LAB_INSTANCE_ID}" \
  aws ec2 wait instance-running \
    --instance-ids "$LAB_INSTANCE_ID" \
    --region "$AWS_REGION" \
    --no-cli-pager

run_logged \
  "$LAB_EC2_LOG" \
  "aws ec2 wait instance-status-ok --instance-ids ${LAB_INSTANCE_ID}" \
  aws ec2 wait instance-status-ok \
    --instance-ids "$LAB_INSTANCE_ID" \
    --region "$AWS_REGION" \
    --no-cli-pager

LAB_PUBLIC_IP="$(
  aws ec2 describe-instances \
    --instance-ids "$LAB_INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text \
    --region "$AWS_REGION" \
    --no-cli-pager
)"

LAB_VOLUME_ID="$(
  aws ec2 describe-instances \
    --instance-ids "$LAB_INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].BlockDeviceMappings[0].Ebs.VolumeId' \
    --output text \
    --region "$AWS_REGION" \
    --no-cli-pager
)"

if [[ -z "$LAB_PUBLIC_IP" || "$LAB_PUBLIC_IP" == "None" ]]; then
  printf 'Instance does not have a public IPv4 address.\n' >&2
  exit 1
fi

persist_env_value LAB_PUBLIC_IP "$LAB_PUBLIC_IP"
persist_env_value LAB_VOLUME_ID "$LAB_VOLUME_ID"

run_logged \
  "$LAB_EC2_LOG" \
  "aws ec2 describe-instances --instance-ids ${LAB_INSTANCE_ID} <limited fields>" \
  aws ec2 describe-instances \
    --instance-ids "$LAB_INSTANCE_ID" \
    --query 'Reservations[].Instances[].{InstanceId:InstanceId,State:State.Name,InstanceType:InstanceType,ImageId:ImageId,VpcId:VpcId,SubnetId:SubnetId,PublicIpAddress:PublicIpAddress,SecurityGroups:SecurityGroups,BlockDevices:BlockDeviceMappings[].{DeviceName:DeviceName,VolumeId:Ebs.VolumeId,DeleteOnTermination:Ebs.DeleteOnTermination}}' \
    --region "$AWS_REGION" \
    --no-cli-pager

run_logged \
  "$LAB_EC2_LOG" \
  "aws ec2 describe-volumes --volume-ids ${LAB_VOLUME_ID} <size type encryption state>" \
  aws ec2 describe-volumes \
    --volume-ids "$LAB_VOLUME_ID" \
    --query 'Volumes[].{VolumeId:VolumeId,SizeGiB:Size,VolumeType:VolumeType,Encrypted:Encrypted,State:State}' \
    --region "$AWS_REGION" \
    --no-cli-pager

LAB_HTTP_READY=0
for LAB_HTTP_ATTEMPT in {1..36}; do
  if LAB_HEALTH_BODY="$(curl --fail --silent --show-error --connect-timeout 3 --max-time 5 "http://${LAB_PUBLIC_IP}/health" 2>/dev/null)" && \
     [[ "$LAB_HEALTH_BODY" == "OK" ]]; then
    LAB_HTTP_READY=1
    break
  fi
  sleep 10
done

if [[ "$LAB_HTTP_READY" != "1" ]]; then
  printf 'External /health did not become ready in time.\n' >&2
  exit 1
fi

run_logged \
  "$LAB_SSH_LOG" \
  "ssh -i <protected-key> -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=<protected-known-hosts> ec2-user@${LAB_PUBLIC_IP} \"printf 'ssh_connection=PASS\\nremote_user='; id -un; printf 'remote_host='; hostname\"" \
  ssh \
    -i "$LAB_PRIVATE_KEY_PATH" \
    -o BatchMode=yes \
    -o ConnectTimeout=10 \
    -o StrictHostKeyChecking=accept-new \
    -o UserKnownHostsFile="${LAB_SECRET_DIR}/known_hosts" \
    "ec2-user@${LAB_PUBLIC_IP}" \
    "printf 'ssh_connection=PASS\\nremote_user='; id -un; printf 'remote_host='; hostname"

run_logged \
  "$LAB_EC2_LOG" \
  "ssh -i <protected-key> ec2-user@${LAB_PUBLIC_IP} <nginx, localhost, outbound checks>" \
  ssh \
    -i "$LAB_PRIVATE_KEY_PATH" \
    -o BatchMode=yes \
    -o ConnectTimeout=10 \
    -o StrictHostKeyChecking=accept-new \
    -o UserKnownHostsFile="${LAB_SECRET_DIR}/known_hosts" \
    "ec2-user@${LAB_PUBLIC_IP}" \
    "printf 'nginx='; systemctl is-active nginx; printf 'localhost-root-status='; curl --silent --output /dev/null --write-out '%{http_code}\\n' http://localhost/; printf 'localhost-health-status='; curl --silent --output /dev/null --write-out '%{http_code}\\n' http://localhost/health; printf 'localhost-health-body='; curl --fail --silent http://localhost/health; printf '\\noutbound='; curl --fail --silent https://example.com/ >/dev/null && printf 'success\\n'"

run_logged \
  "$LAB_EXTERNAL_LOG" \
  "curl --include http://${LAB_PUBLIC_IP}/health" \
  curl \
    --include \
    --fail \
    --silent \
    --show-error \
    --connect-timeout 5 \
    --max-time 15 \
    "http://${LAB_PUBLIC_IP}/health"

run_logged \
  "$LAB_HTTP_200_LOG" \
  "curl http://${LAB_PUBLIC_IP}/health <expect HTTP 200 and body OK>" \
  zsh -c '
    lab_url="$1"
    lab_body_file="$(mktemp)"
    trap '\''rm -f "$lab_body_file"'\'' EXIT

    lab_http_status="$(curl \
      --silent \
      --show-error \
      --connect-timeout 5 \
      --max-time 15 \
      --output "$lab_body_file" \
      --write-out "%{http_code}" \
      "$lab_url")"
    lab_body="$(cat "$lab_body_file")"

    printf "http_status=%s\\n" "$lab_http_status"
    printf "response_body=%s\\n" "$lab_body"

    if [[ "$lab_http_status" != "200" || "$lab_body" != "OK" ]]; then
      printf "http_200_ok=FAIL\\n" >&2
      exit 1
    fi

    printf "http_200_ok=PASS\\n"
  ' zsh "http://${LAB_PUBLIC_IP}/health"

printf 'Compute provisioning and web verification complete.\n'
