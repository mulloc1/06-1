# AWS CLI Command Guide — 06-1 Cloud Lab

> 이 문서는 AWS 명령을 실행하지 않은 상태에서 작성한 실행 가이드다.
> 명령은 저장소 루트(`06-1/`)에서 위에서 아래 순서대로 실행한다.
> 실제 자격 증명, MFA 코드, SSH 개인 키는 로그나 Git에 남기지 않는다.

## 고정 구성

| 항목 | 값 |
| --- | --- |
| Region | `ap-northeast-2` |
| Availability Zone | `ap-northeast-2a` |
| VPC CIDR | `10.0.0.0/16` |
| Public Subnet CIDR | `10.0.1.0/24` |
| Instance | Amazon Linux 2023, `t3.micro` |
| Web server | Nginx, TCP 80 |
| Health endpoint | `GET /health` → `200 OK`, body `OK` |
| Project tag | `Project=codyssey-06-1` |

---

## Step 0 — `.env` 준비와 안전한 로딩

### 목적

장기 Access Key, MFA 임시 자격 증명, 리전, 리소스 ID를 Git에서 제외된 로컬 `.env`로 관리한다.

### 입력할 명령어

> `.env`가 이미 생성되어 있으면 덮어쓰지 않는다. 실제 값은 로컬 `.env`에만 입력한다.

```bash
cp .env.example .env
chmod 600 .env
```

현재 셸에 값을 로드한다.

```bash
set -a
source ./.env
set +a
```

환경 변수 값을 출력하지 않고 필수 설정만 확인한다.

```bash
: "${AWS_REGION:?AWS_REGION is required}"
: "${LAB_PROJECT:?LAB_PROJECT is required}"
: "${LAB_RESOURCE_PREFIX:?LAB_RESOURCE_PREFIX is required}"
: "${LAB_VPC_CIDR:?LAB_VPC_CIDR is required}"
: "${LAB_SUBNET_CIDR:?LAB_SUBNET_CIDR is required}"
```

명령 결과로 얻은 값을 노출하지 않고 `.env`에 저장하는 함수를 현재 zsh 세션에 등록한다.

```bash
persist_env_key() {
  local lab_env_key="$1"

  if [[ ! "$lab_env_key" =~ ^[A-Z][A-Z0-9_]*$ ]]; then
    printf 'Invalid environment key: %s\n' "$lab_env_key" >&2
    return 1
  fi

  export LAB_ENV_KEY_TO_WRITE="$lab_env_key"
  umask 077

  awk '
    BEGIN {
      key = ENVIRON["LAB_ENV_KEY_TO_WRITE"]
      value = ENVIRON[key]
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
  ' .env > .env.tmp

  chmod 600 .env.tmp
  mv .env.tmp .env
  unset LAB_ENV_KEY_TO_WRITE
}
```

### 예상 결과

- `.env` 권한이 `600`이다.
- `.env`는 Git에서 무시되고 `.env.example`은 추적 가능하다.
- 환경 변수 값은 터미널에 출력되지 않는다.

### 저장할 로그

없음. `.env` 내용과 자격 증명은 증거 로그가 아니다.

### 실패 시 확인 순서

1. 저장소 루트에서 실행했는지 확인한다.
2. `.env` 파일 존재 여부를 확인한다.
3. 값 주변에 불필요한 공백이나 따옴표가 없는지 확인한다.
4. `source ./.env`를 다시 실행한다.

---

## Step 1 — IAM 사용자와 최소 권한 정책

### 목적

루트 Access Key를 만들지 않고, 브라우저에서 로그인한 AWS Console 자격으로 임시 부트스트랩 세션을 받아 IAM 사용자와 최소 권한 정책을 CLI로 생성한다. 이후 실습은 MFA가 적용된 `lab-cloud-web` 사용자로만 수행한다.

### 입력할 명령어

> 루트 계정 MFA를 먼저 활성화한다. 이 단계의 `aws login`, MFA 등록, Access Key 생성 명령은 `run_logged`로 실행하지 않는다.

기존 환경 자격 증명이 부트스트랩 프로필보다 우선하지 않도록 현재 셸에서만 제거한 후 브라우저 로그인을 시작한다. 설치된 AWS CLI가 `2.32.0` 이상이어야 한다.

```bash
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE

aws login \
  --profile bootstrap \
  --region "$AWS_REGION"
```

열린 브라우저에서 현재 AWS 계정의 루트 Console 세션을 선택한다. 로그인 후 임시 자격으로 호출할 수 있는지만 확인한다.

```bash
aws sts get-caller-identity \
  --profile bootstrap \
  --region "$AWS_REGION" \
  --no-cli-pager
```

정책 ARN 구성에 사용할 계정 ID를 변수로 받는다. 최소 권한 정책 템플릿은 계정별 값이 없으므로 그대로 사용한다.

```bash
LAB_BOOTSTRAP_ACCOUNT_ID="$(
  aws sts get-caller-identity \
    --query Account \
    --output text \
    --profile bootstrap \
    --region "$AWS_REGION" \
    --no-cli-pager
)"
```

CLI 전용 IAM 사용자를 생성한다. `create-login-profile`을 호출하지 않으므로 Console 비밀번호는 만들어지지 않는다.

```bash
aws iam create-user \
  --user-name "$LAB_RESOURCE_PREFIX" \
  --tags Key=Project,Value="$LAB_PROJECT" \
  --profile bootstrap \
  --region "$AWS_REGION" \
  --no-cli-pager
```

고객 관리형 정책을 생성하고 사용자에게 직접 연결한다. 그룹은 만들지 않는다.

```bash
LAB_POLICY_ARN="arn:aws:iam::${LAB_BOOTSTRAP_ACCOUNT_ID}:policy/lab-cloud-web-policy"

aws iam create-policy \
  --policy-name lab-cloud-web-policy \
  --description "Least privilege for the codyssey 06-1 EC2 and VPC lab" \
  --policy-document file://docs/iam/lab-cloud-web-policy.template.json \
  --tags Key=Project,Value="$LAB_PROJECT" \
  --profile bootstrap \
  --region "$AWS_REGION" \
  --no-cli-pager

aws iam attach-user-policy \
  --user-name "$LAB_RESOURCE_PREFIX" \
  --policy-arn "$LAB_POLICY_ARN" \
  --profile bootstrap \
  --region "$AWS_REGION" \
  --no-cli-pager
```

Virtual MFA 장치의 QR 이미지를 임시 경로에 만든다. 이 QR은 비밀정보이므로 저장소나 로그에 남기지 않는다.

```bash
LAB_MFA_SERIAL="$(
  aws iam create-virtual-mfa-device \
    --virtual-mfa-device-name "$LAB_RESOURCE_PREFIX" \
    --outfile /tmp/lab-cloud-web-mfa.png \
    --bootstrap-method QRCodePNG \
    --tags Key=Project,Value="$LAB_PROJECT" \
    --query VirtualMFADevice.SerialNumber \
    --output text \
    --profile bootstrap \
    --region "$AWS_REGION" \
    --no-cli-pager
)"

open /tmp/lab-cloud-web-mfa.png
```

인증 앱으로 QR을 스캔한 뒤 연속된 코드 두 개를 입력한다. 첫 번째 코드를 입력한 후 코드가 갱신되면 두 번째 코드를 입력한다.

```bash
read -s "LAB_MFA_CODE_1?First MFA code: "
printf '\n'
read -s "LAB_MFA_CODE_2?Next MFA code after it changes: "
printf '\n'

aws iam enable-mfa-device \
  --user-name "$LAB_RESOURCE_PREFIX" \
  --serial-number "$LAB_MFA_SERIAL" \
  --authentication-code1 "$LAB_MFA_CODE_1" \
  --authentication-code2 "$LAB_MFA_CODE_2" \
  --profile bootstrap \
  --region "$AWS_REGION" \
  --no-cli-pager

unset LAB_MFA_CODE_1 LAB_MFA_CODE_2

export AWS_MFA_SERIAL="$LAB_MFA_SERIAL"
persist_env_key AWS_MFA_SERIAL
```

Access Key를 출력하지 않고 현재 셸 변수로 받은 뒤 로컬 `.env`에만 저장한다.

```bash
read -r AWS_BASE_ACCESS_KEY_ID AWS_BASE_SECRET_ACCESS_KEY <<< "$(
  aws iam create-access-key \
    --user-name "$LAB_RESOURCE_PREFIX" \
    --query 'AccessKey.[AccessKeyId,SecretAccessKey]' \
    --output text \
    --profile bootstrap \
    --region "$AWS_REGION" \
    --no-cli-pager
)"

export AWS_BASE_ACCESS_KEY_ID AWS_BASE_SECRET_ACCESS_KEY
persist_env_key AWS_BASE_ACCESS_KEY_ID
persist_env_key AWS_BASE_SECRET_ACCESS_KEY

unset AWS_BASE_ACCESS_KEY_ID AWS_BASE_SECRET_ACCESS_KEY
```

정책, MFA, Access Key 메타데이터만 확인한 뒤 부트스트랩 로그인 캐시와 임시 파일을 제거한다.

```bash
aws iam list-attached-user-policies \
  --user-name "$LAB_RESOURCE_PREFIX" \
  --profile bootstrap \
  --region "$AWS_REGION" \
  --no-cli-pager

aws iam list-mfa-devices \
  --user-name "$LAB_RESOURCE_PREFIX" \
  --query 'MFADevices[].SerialNumber' \
  --profile bootstrap \
  --region "$AWS_REGION" \
  --no-cli-pager

aws iam list-access-keys \
  --user-name "$LAB_RESOURCE_PREFIX" \
  --query 'AccessKeyMetadata[].{Status:Status,CreateDate:CreateDate}' \
  --profile bootstrap \
  --region "$AWS_REGION" \
  --no-cli-pager

aws logout --profile bootstrap

rm -f \
  /tmp/lab-cloud-web-mfa.png

unset LAB_BOOTSTRAP_ACCOUNT_ID LAB_POLICY_ARN LAB_MFA_SERIAL
```

### 예상 결과

- 사용자에게 `AdministratorAccess`가 없다.
- S3, RDS, Lambda, 다른 IAM 사용자 관리 권한이 없다.
- EC2/VPC 작업은 서울 리전과 MFA 세션으로 제한된다.

### 저장할 로그

없음. 부트스트랩 호출자 정보, MFA QR, 코드, Access Key는 증거 로그에 남기지 않는다. 비밀값이 없는 정책 템플릿은 `docs/iam/lab-cloud-web-policy.template.json`에 보관한다.

### 실패 시 확인 순서

1. `aws --version`이 `2.32.0` 이상인지 확인한다.
2. `aws login` 브라우저에서 올바른 AWS 계정 세션을 선택했는지 확인한다.
3. `EntityAlreadyExists`이면 해당 생성 명령을 반복하지 말고 조회 명령으로 기존 리소스를 확인한다.
4. MFA QR 생성 후 연결에 실패했다면 QR 생성 명령을 반복하지 말고 기존 장치 상태부터 확인한다.
5. 정책이 `lab-cloud-web` 사용자에게 연결됐고 리전 조건이 `ap-northeast-2`인지 확인한다.
6. 권한 부족 시 `AdministratorAccess`를 붙이지 말고 거부된 단일 액션만 검토한다.

---

## Step 2 — MFA 임시 세션 발급

### 목적

장기 Access Key로 AWS 리소스를 직접 관리하지 않고, MFA가 포함된 12시간 임시 자격 증명을 발급한다.

### 입력할 명령어

`.env`에서 장기 키와 MFA ARN을 읽었는지 확인한다. 값은 출력하지 않는다.

```bash
: "${AWS_BASE_ACCESS_KEY_ID:?AWS_BASE_ACCESS_KEY_ID is required}"
: "${AWS_BASE_SECRET_ACCESS_KEY:?AWS_BASE_SECRET_ACCESS_KEY is required}"
: "${AWS_MFA_SERIAL:?AWS_MFA_SERIAL is required}"
```

MFA 코드를 셸 히스토리에 남기지 않고 입력한 뒤 세션 키를 변수에 받는다. 이 명령은 `run_logged`로 실행하지 않는다.

```bash
read -s "LAB_MFA_CODE?MFA code: "
printf '\n'

read -r LAB_SESSION_ACCESS_KEY LAB_SESSION_SECRET_KEY LAB_SESSION_TOKEN <<< "$(
  AWS_ACCESS_KEY_ID="$AWS_BASE_ACCESS_KEY_ID" \
  AWS_SECRET_ACCESS_KEY="$AWS_BASE_SECRET_ACCESS_KEY" \
  AWS_SESSION_TOKEN= \
  aws sts get-session-token \
    --serial-number "$AWS_MFA_SERIAL" \
    --token-code "$LAB_MFA_CODE" \
    --duration-seconds 43200 \
    --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
    --output text \
    --region "$AWS_REGION" \
    --no-cli-pager
)"

unset LAB_MFA_CODE

export AWS_ACCESS_KEY_ID="$LAB_SESSION_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$LAB_SESSION_SECRET_KEY"
export AWS_SESSION_TOKEN="$LAB_SESSION_TOKEN"

unset LAB_SESSION_ACCESS_KEY LAB_SESSION_SECRET_KEY LAB_SESSION_TOKEN

persist_env_key AWS_ACCESS_KEY_ID
persist_env_key AWS_SECRET_ACCESS_KEY
persist_env_key AWS_SESSION_TOKEN
```

### 예상 결과

- 현재 셸과 `.env`의 `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`이 임시 세션 값으로 갱신된다.
- 키 값 자체는 터미널이나 로그에 출력되지 않는다.

### 저장할 로그

세션 발급 결과는 저장하지 않는다. 다음 Step의 제한된 검증만 기록한다.

### 실패 시 확인 순서

1. `AWS_MFA_SERIAL`이 `arn:aws:iam::<ACCOUNT_ID>:mfa/lab-cloud-web` 형식인지 확인한다.
2. MFA 코드가 만료되기 전에 다시 입력한다.
3. Base Key가 `lab-cloud-web` 사용자의 활성 Access Key인지 확인한다.
4. 시스템 시각이 자동 동기화되어 있는지 확인한다.

---

## Step 3 — 안전한 명령 로그 함수와 IAM 검증

### 목적

민감 값을 제외하고 실행 시각, 명령, 표준 출력, 오류, 종료 코드를 텍스트 증거로 남긴다.

### 입력할 명령어

```bash
LAB_LOG_DIR="docs/evidence/logs"
mkdir -p "$LAB_LOG_DIR"
set -o pipefail

run_logged() {
  local lab_log_file="$1"
  shift

  {
    printf '\n[%s] $' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf ' %q' "$@"
    printf '\n'

    "$@"
    local lab_status=$?

    printf '[exit=%d]\n' "$lab_status"
    return "$lab_status"
  } 2>&1 | tee -a "$lab_log_file"
}
```

호출자가 올바른 사용자인지만 Boolean으로 기록한다.

```bash
run_logged \
  "$LAB_LOG_DIR/01-iam-validation.log" \
  aws sts get-caller-identity \
  --query "contains(Arn, 'user/lab-cloud-web')" \
  --output text \
  --region "$AWS_REGION" \
  --no-cli-pager
```

허용·거부 범위를 확인한다.

```bash
run_logged \
  "$LAB_LOG_DIR/01-iam-validation.log" \
  aws ec2 describe-vpcs \
  --max-results 5 \
  --region "$AWS_REGION" \
  --no-cli-pager

run_logged \
  "$LAB_LOG_DIR/01-iam-validation.log" \
  aws s3 ls \
  --region "$AWS_REGION" \
  --no-cli-pager

run_logged \
  "$LAB_LOG_DIR/01-iam-validation.log" \
  aws iam list-users \
  --max-items 1 \
  --region "$AWS_REGION" \
  --no-cli-pager
```

### 예상 결과

- Caller 검증: `True`
- EC2 조회: 성공
- S3와 IAM 사용자 목록: `AccessDenied`

### 저장할 로그

`docs/evidence/logs/01-iam-validation.log`

### 실패 시 확인 순서

1. MFA 세션 변수가 비어 있지 않은지 값 출력 없이 `${VAR:?}`로 확인한다.
2. 세션 만료 여부를 확인하고 Step 2를 다시 수행한다.
3. IAM 정책의 MFA 및 리전 조건을 확인한다.

> `run_logged`에는 `env`, `set`, `export -p`, `.env` 출력, `aws configure list`, `aws --debug`, `get-session-token`, KeyMaterial 출력을 절대 전달하지 않는다.

---

## Step 4 — VPC, Subnet, IGW, Route Table 생성

### 목적

외부 통신이 가능한 최소 퍼블릭 네트워크를 구성한다.

### 입력할 명령어

VPC를 생성하고 ID를 `.env`에 저장한다.

```bash
LAB_VPC_ID="$(aws ec2 create-vpc \
  --cidr-block "$LAB_VPC_CIDR" \
  --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${LAB_RESOURCE_PREFIX}-vpc},{Key=Project,Value=${LAB_PROJECT}}]" \
  --query 'Vpc.VpcId' \
  --output text \
  --region "$AWS_REGION" \
  --no-cli-pager)"
export LAB_VPC_ID
persist_env_key LAB_VPC_ID

aws ec2 wait vpc-available \
  --vpc-ids "$LAB_VPC_ID" \
  --region "$AWS_REGION" \
  --no-cli-pager

aws ec2 modify-vpc-attribute \
  --vpc-id "$LAB_VPC_ID" \
  --enable-dns-support '{"Value":true}' \
  --region "$AWS_REGION" \
  --no-cli-pager

aws ec2 modify-vpc-attribute \
  --vpc-id "$LAB_VPC_ID" \
  --enable-dns-hostnames '{"Value":true}' \
  --region "$AWS_REGION" \
  --no-cli-pager
```

Public Subnet을 생성한다.

```bash
LAB_SUBNET_ID="$(aws ec2 create-subnet \
  --vpc-id "$LAB_VPC_ID" \
  --cidr-block "$LAB_SUBNET_CIDR" \
  --availability-zone "$LAB_AZ" \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${LAB_RESOURCE_PREFIX}-public-subnet},{Key=Project,Value=${LAB_PROJECT}}]" \
  --query 'Subnet.SubnetId' \
  --output text \
  --region "$AWS_REGION" \
  --no-cli-pager)"
export LAB_SUBNET_ID
persist_env_key LAB_SUBNET_ID

aws ec2 modify-subnet-attribute \
  --subnet-id "$LAB_SUBNET_ID" \
  --map-public-ip-on-launch \
  --region "$AWS_REGION" \
  --no-cli-pager
```

Internet Gateway를 생성하고 VPC에 연결한다.

```bash
LAB_IGW_ID="$(aws ec2 create-internet-gateway \
  --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${LAB_RESOURCE_PREFIX}-igw},{Key=Project,Value=${LAB_PROJECT}}]" \
  --query 'InternetGateway.InternetGatewayId' \
  --output text \
  --region "$AWS_REGION" \
  --no-cli-pager)"
export LAB_IGW_ID
persist_env_key LAB_IGW_ID

aws ec2 attach-internet-gateway \
  --internet-gateway-id "$LAB_IGW_ID" \
  --vpc-id "$LAB_VPC_ID" \
  --region "$AWS_REGION" \
  --no-cli-pager
```

Route Table, 기본 경로, Subnet 연결을 생성한다.

```bash
LAB_ROUTE_TABLE_ID="$(aws ec2 create-route-table \
  --vpc-id "$LAB_VPC_ID" \
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${LAB_RESOURCE_PREFIX}-public-rt},{Key=Project,Value=${LAB_PROJECT}}]" \
  --query 'RouteTable.RouteTableId' \
  --output text \
  --region "$AWS_REGION" \
  --no-cli-pager)"
export LAB_ROUTE_TABLE_ID
persist_env_key LAB_ROUTE_TABLE_ID

aws ec2 create-route \
  --route-table-id "$LAB_ROUTE_TABLE_ID" \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id "$LAB_IGW_ID" \
  --region "$AWS_REGION" \
  --no-cli-pager

LAB_ROUTE_ASSOCIATION_ID="$(aws ec2 associate-route-table \
  --route-table-id "$LAB_ROUTE_TABLE_ID" \
  --subnet-id "$LAB_SUBNET_ID" \
  --query 'AssociationId' \
  --output text \
  --region "$AWS_REGION" \
  --no-cli-pager)"
export LAB_ROUTE_ASSOCIATION_ID
persist_env_key LAB_ROUTE_ASSOCIATION_ID
```

구성 결과를 기록한다.

```bash
run_logged \
  "$LAB_LOG_DIR/02-network-state.log" \
  aws ec2 describe-vpcs \
  --vpc-ids "$LAB_VPC_ID" \
  --query 'Vpcs[0].{VpcId:VpcId,Cidr:CidrBlock,State:State,Tags:Tags}' \
  --region "$AWS_REGION" \
  --no-cli-pager

run_logged \
  "$LAB_LOG_DIR/02-network-state.log" \
  aws ec2 describe-subnets \
  --subnet-ids "$LAB_SUBNET_ID" \
  --query 'Subnets[0].{SubnetId:SubnetId,Cidr:CidrBlock,AZ:AvailabilityZone,PublicIpOnLaunch:MapPublicIpOnLaunch}' \
  --region "$AWS_REGION" \
  --no-cli-pager

run_logged \
  "$LAB_LOG_DIR/02-network-state.log" \
  aws ec2 describe-internet-gateways \
  --internet-gateway-ids "$LAB_IGW_ID" \
  --query 'InternetGateways[0].{InternetGatewayId:InternetGatewayId,Attachments:Attachments}' \
  --region "$AWS_REGION" \
  --no-cli-pager

run_logged \
  "$LAB_LOG_DIR/02-network-state.log" \
  aws ec2 describe-route-tables \
  --route-table-ids "$LAB_ROUTE_TABLE_ID" \
  --query 'RouteTables[0].{RouteTableId:RouteTableId,Routes:Routes,Associations:Associations}' \
  --region "$AWS_REGION" \
  --no-cli-pager
```

### 예상 결과

- VPC: `10.0.0.0/16`, `available`
- Subnet: `10.0.1.0/24`, `MapPublicIpOnLaunch=true`
- IGW가 VPC에 `available` 상태로 연결됨
- Route Table에 `local`과 `0.0.0.0/0 → igw-*`가 존재
- Public Subnet이 해당 Route Table과 명시적으로 연결됨

### 저장할 로그

`docs/evidence/logs/02-network-state.log`

### 실패 시 확인 순서

1. 현재 리전과 AZ가 일치하는지 확인한다.
2. `.env`의 VPC/Subnet ID가 실제 반환값인지 확인한다.
3. IGW가 같은 VPC에 연결됐는지 확인한다.
4. Route Table 연결 대상이 올바른 Subnet인지 확인한다.

---

## Step 5 — Security Group과 SSH Key 생성

### 목적

HTTP만 전체에 공개하고 SSH는 학습자의 현재 공인 IP로 제한한다.

### 입력할 명령어

공인 IP를 확인하고 `/32` CIDR을 `.env`에 저장한다.

```bash
LAB_LEARNER_IP_CIDR="$(curl -4 -s https://checkip.amazonaws.com)/32"
export LAB_LEARNER_IP_CIDR
persist_env_key LAB_LEARNER_IP_CIDR
```

Security Group을 만들고 두 개의 인바운드 규칙만 추가한다.

```bash
LAB_SECURITY_GROUP_ID="$(aws ec2 create-security-group \
  --group-name lab-web-sg \
  --description 'Least-privilege SG for 06-1 Nginx lab' \
  --vpc-id "$LAB_VPC_ID" \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=lab-web-sg},{Key=Project,Value=${LAB_PROJECT}}]" \
  --query 'GroupId' \
  --output text \
  --region "$AWS_REGION" \
  --no-cli-pager)"
export LAB_SECURITY_GROUP_ID
persist_env_key LAB_SECURITY_GROUP_ID

aws ec2 authorize-security-group-ingress \
  --group-id "$LAB_SECURITY_GROUP_ID" \
  --ip-permissions "IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges=[{CidrIp=0.0.0.0/0,Description='Public HTTP'}]" \
  --region "$AWS_REGION" \
  --no-cli-pager

aws ec2 authorize-security-group-ingress \
  --group-id "$LAB_SECURITY_GROUP_ID" \
  --ip-permissions "IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges=[{CidrIp=${LAB_LEARNER_IP_CIDR},Description='Learner SSH'}]" \
  --region "$AWS_REGION" \
  --no-cli-pager
```

Security Group 상태를 기록한다.

```bash
run_logged \
  "$LAB_LOG_DIR/03-security-group.log" \
  aws ec2 describe-security-groups \
  --group-ids "$LAB_SECURITY_GROUP_ID" \
  --query 'SecurityGroups[0].{GroupId:GroupId,Inbound:IpPermissions,Outbound:IpPermissionsEgress}' \
  --region "$AWS_REGION" \
  --no-cli-pager
```

개인 키를 저장소 밖에 생성한다. 이 명령은 `run_logged`로 실행하지 않는다.

```bash
mkdir -p ~/.ssh
umask 077

aws ec2 create-key-pair \
  --key-name "$LAB_KEY_NAME" \
  --key-type ed25519 \
  --key-format pem \
  --tag-specifications "ResourceType=key-pair,Tags=[{Key=Name,Value=${LAB_KEY_NAME}},{Key=Project,Value=${LAB_PROJECT}}]" \
  --query 'KeyMaterial' \
  --output text \
  --region "$AWS_REGION" \
  --no-cli-pager \
  > "$HOME/.ssh/${LAB_KEY_NAME}.pem"

chmod 400 "$HOME/.ssh/${LAB_KEY_NAME}.pem"
```

### 예상 결과

- 인바운드 규칙은 TCP 80 전체와 TCP 22 학습자 `/32` 두 개뿐이다.
- 전체 포트 허용 규칙이 없다.
- 개인 키 권한은 `400`이며 Git 작업 폴더 밖에 있다.

### 저장할 로그

`docs/evidence/logs/03-security-group.log`

### 실패 시 확인 순서

1. 학습자 CIDR이 IPv4 `/32` 형식인지 확인한다.
2. Security Group이 실습 VPC 안에 있는지 확인한다.
3. SSH Key 파일이 이미 존재하면 덮어쓰지 말고 Key Pair 상태부터 확인한다.

---

## Step 6 — Amazon Linux 2023 EC2 실행

### 목적

Public Subnet에 `t3.micro` 한 대를 실행하고 8 GiB gp3, Public IPv4, IMDSv2를 적용한다.

### 입력할 명령어

최신 Amazon Linux 2023 x86_64 AMI를 조회하고 `.env`에 저장한다.

```bash
LAB_AMI_ID="$(aws ec2 describe-images \
  --owners amazon \
  --filters \
    'Name=name,Values=al2023-ami-2023.*-kernel-6.1-x86_64' \
    'Name=architecture,Values=x86_64' \
    'Name=state,Values=available' \
  --query 'reverse(sort_by(Images,&CreationDate))[0].ImageId' \
  --output text \
  --region "$AWS_REGION" \
  --no-cli-pager)"
export LAB_AMI_ID
persist_env_key LAB_AMI_ID
```

EC2를 실행한다.

```bash
LAB_INSTANCE_ID="$(aws ec2 run-instances \
  --image-id "$LAB_AMI_ID" \
  --instance-type "$LAB_INSTANCE_TYPE" \
  --count 1 \
  --key-name "$LAB_KEY_NAME" \
  --subnet-id "$LAB_SUBNET_ID" \
  --security-group-ids "$LAB_SECURITY_GROUP_ID" \
  --associate-public-ip-address \
  --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":8,"VolumeType":"gp3","DeleteOnTermination":true,"Encrypted":true}}]' \
  --metadata-options 'HttpTokens=required,HttpEndpoint=enabled' \
  --tag-specifications \
    "ResourceType=instance,Tags=[{Key=Name,Value=${LAB_RESOURCE_PREFIX}-ec2},{Key=Project,Value=${LAB_PROJECT}}]" \
    "ResourceType=volume,Tags=[{Key=Name,Value=${LAB_RESOURCE_PREFIX}-root-volume},{Key=Project,Value=${LAB_PROJECT}}]" \
  --query 'Instances[0].InstanceId' \
  --output text \
  --region "$AWS_REGION" \
  --no-cli-pager)"
export LAB_INSTANCE_ID
persist_env_key LAB_INSTANCE_ID

aws ec2 wait instance-running \
  --instance-ids "$LAB_INSTANCE_ID" \
  --region "$AWS_REGION" \
  --no-cli-pager

aws ec2 wait instance-status-ok \
  --instance-ids "$LAB_INSTANCE_ID" \
  --region "$AWS_REGION" \
  --no-cli-pager
```

Public IPv4와 EBS Volume ID를 저장한다.

```bash
LAB_PUBLIC_IP="$(aws ec2 describe-instances \
  --instance-ids "$LAB_INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text \
  --region "$AWS_REGION" \
  --no-cli-pager)"
export LAB_PUBLIC_IP
persist_env_key LAB_PUBLIC_IP

LAB_VOLUME_ID="$(aws ec2 describe-instances \
  --instance-ids "$LAB_INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].BlockDeviceMappings[0].Ebs.VolumeId' \
  --output text \
  --region "$AWS_REGION" \
  --no-cli-pager)"
export LAB_VOLUME_ID
persist_env_key LAB_VOLUME_ID
```

인스턴스 구성을 기록한다.

```bash
run_logged \
  "$LAB_LOG_DIR/04-ec2-web-server.log" \
  aws ec2 describe-instances \
  --instance-ids "$LAB_INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].{State:State.Name,Type:InstanceType,PublicIp:PublicIpAddress,SubnetId:SubnetId,SecurityGroups:SecurityGroups,MetadataOptions:MetadataOptions,BlockDevices:BlockDeviceMappings}' \
  --region "$AWS_REGION" \
  --no-cli-pager

run_logged \
  "$LAB_LOG_DIR/04-ec2-web-server.log" \
  aws ec2 describe-volumes \
  --volume-ids "$LAB_VOLUME_ID" \
  --query 'Volumes[0].{VolumeId:VolumeId,Size:Size,Type:VolumeType,Encrypted:Encrypted,State:State}' \
  --region "$AWS_REGION" \
  --no-cli-pager
```

### 예상 결과

- 인스턴스 상태 `running`, 상태 검사 `2/2`
- Type `t3.micro`, Public IPv4 존재
- 올바른 Subnet과 Security Group 연결
- EBS 8 GiB gp3, 암호화
- IMDSv2 `HttpTokens=required`

### 저장할 로그

- `docs/evidence/logs/04-ec2-web-server.log`
- `docs/evidence/logs/04-ssh-connection.log` — 자동 설정 스크립트의 독립 SSH 접속 증거

### 실패 시 확인 순서

1. AMI ID가 `None`이 아닌지 확인한다.
2. AMI 아키텍처와 인스턴스 유형을 확인한다.
3. Subnet과 Security Group이 같은 VPC인지 확인한다.
4. IAM 거부 메시지의 액션만 최소 정책에 추가 검토한다.

---

## Step 7 — Nginx와 `/health` 구성

### 목적

EC2 내부에서 Nginx를 실행하고 `/health`가 고정된 `OK`를 반환하도록 한다.

### 입력할 명령어

SSH로 접속한다.

```bash
ssh -i "$HOME/.ssh/${LAB_KEY_NAME}.pem" \
  "ec2-user@${LAB_PUBLIC_IP}"
```

EC2 내부에서 실행한다.

```bash
sudo dnf install -y nginx
sudo systemctl enable --now nginx
sudo nginx -t

printf 'OK\n' \
  | sudo tee /usr/share/nginx/html/health > /dev/null

printf '<h1>06-1 Cloud Lab - lab-cloud-web-ec2</h1>\n' \
  | sudo tee /usr/share/nginx/html/index.html > /dev/null

systemctl is-active nginx
curl -i http://localhost/
curl -i http://localhost/health
curl -sI https://example.com
```

SSH에서 나온 뒤 같은 검증을 원격 명령으로 로그에 기록한다.

```bash
run_logged \
  "$LAB_LOG_DIR/04-ec2-web-server.log" \
  ssh -i "$HOME/.ssh/${LAB_KEY_NAME}.pem" \
  "ec2-user@${LAB_PUBLIC_IP}" \
  "systemctl is-active nginx && curl -i http://localhost/ && curl -i http://localhost/health && curl -sI https://example.com"
```

### 예상 결과

- Nginx 상태 `active`
- localhost `/`와 `/health` 모두 200
- `/health` 본문 `OK`
- 인스턴스에서 외부 HTTPS 요청 성공

### 저장할 로그

`docs/evidence/logs/04-ec2-web-server.log`

### 실패 시 확인 순서

1. `systemctl status nginx` 확인
2. `journalctl -u nginx --since '10 minutes ago'` 확인
3. `sudo nginx -t` 확인
4. Route Table과 SG 아웃바운드 확인

---

## Step 8 — 외부 접속과 포트 검증

### 목적

학습자 Mac에서 Public IPv4의 `/health`가 정상 응답하고 사용하지 않는 포트가 닫혀 있는지 검증한다.

### 입력할 명령어

```bash
run_logged \
  "$LAB_LOG_DIR/05-external-health.log" \
  curl --connect-timeout 10 -i \
  "http://${LAB_PUBLIC_IP}/health"

run_logged \
  "$LAB_LOG_DIR/05-external-health.log" \
  curl --connect-timeout 10 -i \
  "http://${LAB_PUBLIC_IP}/"

run_logged \
  "$LAB_LOG_DIR/05-external-health.log" \
  nc -vz -w 5 "$LAB_PUBLIC_IP" 8080

run_logged \
  "$LAB_LOG_DIR/05-external-health.log" \
  nc -vz -w 5 "$LAB_PUBLIC_IP" 3306
```

### 예상 결과

- `/health`: 200, 본문 `OK`
- `/`: 커스텀 제목 출력
- 8080과 3306: 연결 실패
- 사용자가 별도로 `docs/evidence/01-external-health.png` 스크린샷을 추가

### 저장할 로그

- `docs/evidence/logs/05-external-health.log`
- `docs/evidence/logs/05-http-200-ok.log` — 자동 설정 스크립트의 상태 코드·본문 판정

### 실패 시 확인 순서

1. 인스턴스 내부 localhost 확인
2. Security Group TCP 80 확인
3. Public IPv4 확인
4. Route Table의 `0.0.0.0/0 → IGW`와 Subnet 연결 확인
5. IGW의 VPC 연결 상태 확인

---

## Step 9 — 트러블슈팅 사례 재현과 복구

### 목적

실제 장애가 없었을 경우 TCP 80 규칙 누락을 통제된 방식으로 재현하고 즉시 원상 복구한다.

### 입력할 명령어

정상 상태를 먼저 기록한 뒤 TCP 80 규칙만 제거한다.

```bash
run_logged \
  "$LAB_LOG_DIR/06-troubleshooting-before.log" \
  aws ec2 describe-security-groups \
  --group-ids "$LAB_SECURITY_GROUP_ID" \
  --query 'SecurityGroups[0].IpPermissions' \
  --region "$AWS_REGION" \
  --no-cli-pager

aws ec2 revoke-security-group-ingress \
  --group-id "$LAB_SECURITY_GROUP_ID" \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0 \
  --region "$AWS_REGION" \
  --no-cli-pager
```

외부 실패와 내부 성공을 기록한다.

```bash
run_logged \
  "$LAB_LOG_DIR/06-troubleshooting-before.log" \
  curl --connect-timeout 10 -i \
  "http://${LAB_PUBLIC_IP}/health"

run_logged \
  "$LAB_LOG_DIR/06-troubleshooting-before.log" \
  ssh -i "$HOME/.ssh/${LAB_KEY_NAME}.pem" \
  "ec2-user@${LAB_PUBLIC_IP}" \
  "curl -i http://localhost/health"
```

TCP 80 규칙을 원래대로 복구한다.

```bash
aws ec2 authorize-security-group-ingress \
  --group-id "$LAB_SECURITY_GROUP_ID" \
  --ip-permissions "IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges=[{CidrIp=0.0.0.0/0,Description='Public HTTP'}]" \
  --region "$AWS_REGION" \
  --no-cli-pager

run_logged \
  "$LAB_LOG_DIR/07-troubleshooting-after.log" \
  aws ec2 describe-security-groups \
  --group-ids "$LAB_SECURITY_GROUP_ID" \
  --query 'SecurityGroups[0].IpPermissions' \
  --region "$AWS_REGION" \
  --no-cli-pager

run_logged \
  "$LAB_LOG_DIR/07-troubleshooting-after.log" \
  curl --connect-timeout 10 -i \
  "http://${LAB_PUBLIC_IP}/health"
```

### 예상 결과

- TCP 80 제거 후 외부 요청 시간 초과
- 같은 시점 localhost 요청은 200
- TCP 80 복구 후 외부 요청 200
- SSH 22와 아웃바운드 규칙은 변경되지 않음

### 저장할 로그

- `docs/evidence/logs/06-troubleshooting-before.log`
- `docs/evidence/logs/07-troubleshooting-after.log`

### 실패 시 확인 순서

1. HTTP 규칙이 정확히 한 번만 존재하는지 확인한다.
2. 복구 명령이 성공하기 전까지 실습을 종료하지 않는다.
3. 중복 규칙 오류가 나면 현재 SG 상태를 조회하고 정상 상태라면 추가하지 않는다.

---

## Step 10 — 정리 전 상태 기록과 리소스 삭제

> 권장 실행 방법: 먼저 `./scripts/cleanup-server.sh`로 삭제 대상을 조회하고, 모든 제출
> 증거를 확보한 뒤 `./scripts/cleanup-server.sh execute`를 실행한다. `--execute`도 동일하게
> 동작한다. 아래 명령은 자동화
> 스크립트가 수행하는 삭제 순서와 개별 명령을 검토하기 위한 참고 자료다.

### 목적

모든 증거를 확보한 후 종속 리소스부터 삭제해 비용 발생을 중단한다.

### 입력할 명령어

삭제 대상을 기록한다.

```bash
run_logged \
  "$LAB_LOG_DIR/08-cleanup-before.log" \
  aws ec2 describe-instances \
  --instance-ids "$LAB_INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].{InstanceId:InstanceId,State:State.Name,VolumeIds:BlockDeviceMappings[*].Ebs.VolumeId,PublicIp:PublicIpAddress}' \
  --region "$AWS_REGION" \
  --no-cli-pager

run_logged \
  "$LAB_LOG_DIR/08-cleanup-before.log" \
  aws ec2 describe-vpcs \
  --vpc-ids "$LAB_VPC_ID" \
  --region "$AWS_REGION" \
  --no-cli-pager
```

EC2를 먼저 종료하고 완전히 종료될 때까지 기다린다.

```bash
aws ec2 terminate-instances \
  --instance-ids "$LAB_INSTANCE_ID" \
  --region "$AWS_REGION" \
  --no-cli-pager

aws ec2 wait instance-terminated \
  --instance-ids "$LAB_INSTANCE_ID" \
  --region "$AWS_REGION" \
  --no-cli-pager
```

키와 Security Group을 삭제한다.

```bash
aws ec2 delete-key-pair \
  --key-name "$LAB_KEY_NAME" \
  --region "$AWS_REGION" \
  --no-cli-pager

aws ec2 delete-security-group \
  --group-id "$LAB_SECURITY_GROUP_ID" \
  --region "$AWS_REGION" \
  --no-cli-pager
```

Route Table 연결과 네트워크 리소스를 삭제한다.

```bash
aws ec2 disassociate-route-table \
  --association-id "$LAB_ROUTE_ASSOCIATION_ID" \
  --region "$AWS_REGION" \
  --no-cli-pager

aws ec2 delete-route-table \
  --route-table-id "$LAB_ROUTE_TABLE_ID" \
  --region "$AWS_REGION" \
  --no-cli-pager

aws ec2 delete-subnet \
  --subnet-id "$LAB_SUBNET_ID" \
  --region "$AWS_REGION" \
  --no-cli-pager

aws ec2 detach-internet-gateway \
  --internet-gateway-id "$LAB_IGW_ID" \
  --vpc-id "$LAB_VPC_ID" \
  --region "$AWS_REGION" \
  --no-cli-pager

aws ec2 delete-internet-gateway \
  --internet-gateway-id "$LAB_IGW_ID" \
  --region "$AWS_REGION" \
  --no-cli-pager

aws ec2 delete-vpc \
  --vpc-id "$LAB_VPC_ID" \
  --region "$AWS_REGION" \
  --no-cli-pager
```

삭제 후 상태를 기록한다.

```bash
run_logged \
  "$LAB_LOG_DIR/09-cleanup-after.log" \
  aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=$LAB_PROJECT" \
  --query 'Reservations[].Instances[?State.Name!=`terminated`].[InstanceId,State.Name]' \
  --region "$AWS_REGION" \
  --no-cli-pager

run_logged \
  "$LAB_LOG_DIR/09-cleanup-after.log" \
  aws ec2 describe-volumes \
  --filters "Name=tag:Project,Values=$LAB_PROJECT" \
  --query 'Volumes[].[VolumeId,State]' \
  --region "$AWS_REGION" \
  --no-cli-pager

run_logged \
  "$LAB_LOG_DIR/09-cleanup-after.log" \
  aws ec2 describe-addresses \
  --filters "Name=tag:Project,Values=$LAB_PROJECT" \
  --query 'Addresses[].[AllocationId,PublicIp]' \
  --region "$AWS_REGION" \
  --no-cli-pager

run_logged \
  "$LAB_LOG_DIR/09-cleanup-after.log" \
  aws ec2 describe-internet-gateways \
  --filters "Name=tag:Project,Values=$LAB_PROJECT" \
  --query 'InternetGateways[].[InternetGatewayId,Attachments]' \
  --region "$AWS_REGION" \
  --no-cli-pager

run_logged \
  "$LAB_LOG_DIR/09-cleanup-after.log" \
  aws ec2 describe-vpcs \
  --filters "Name=tag:Project,Values=$LAB_PROJECT" \
  --query 'Vpcs[].[VpcId,State]' \
  --region "$AWS_REGION" \
  --no-cli-pager

run_logged \
  "$LAB_LOG_DIR/09-cleanup-after.log" \
  aws ec2 describe-security-groups \
  --filters "Name=tag:Project,Values=$LAB_PROJECT" \
  --query 'SecurityGroups[].[GroupId,GroupName]' \
  --region "$AWS_REGION" \
  --no-cli-pager

run_logged \
  "$LAB_LOG_DIR/09-cleanup-after.log" \
  aws ec2 describe-subnets \
  --filters "Name=tag:Project,Values=$LAB_PROJECT" \
  --query 'Subnets[].[SubnetId,State]' \
  --region "$AWS_REGION" \
  --no-cli-pager

run_logged \
  "$LAB_LOG_DIR/09-cleanup-after.log" \
  aws ec2 describe-route-tables \
  --filters "Name=tag:Project,Values=$LAB_PROJECT" \
  --query 'RouteTables[].[RouteTableId]' \
  --region "$AWS_REGION" \
  --no-cli-pager

run_logged \
  "$LAB_LOG_DIR/09-cleanup-after.log" \
  aws ec2 describe-key-pairs \
  --filters "Name=tag:Project,Values=$LAB_PROJECT" \
  --query 'KeyPairs[].[KeyPairId,KeyName]' \
  --region "$AWS_REGION" \
  --no-cli-pager
```

모든 AWS 리소스가 사라진 뒤 관리자 Console에서 다음 순서로 IAM을 정리한다.

1. `lab-cloud-web` Access Key 비활성화 및 삭제
2. MFA 장치 해제 및 삭제
3. `lab-cloud-web-policy` 분리
4. IAM 사용자 삭제
5. 고객 관리형 정책 삭제
6. Billing/Cost Explorer 확인

마지막으로 로컬 비밀 파일을 정리한다.

```bash
rm "$HOME/.ssh/${LAB_KEY_NAME}.pem"
rm .env
```

### 예상 결과

- EC2, EBS, EIP, IGW, VPC 조회 결과가 비어 있다.
- Security Group, Subnet, Route Table, Key Pair 조회 결과가 비어 있다.
- 실습 IAM 사용자와 정책이 삭제됐다.
- 로컬 장기 키, 임시 키, SSH 개인 키가 남지 않는다.

### 저장할 로그

- `docs/evidence/logs/08-cleanup-before.log`
- `docs/evidence/logs/09-cleanup-after.log`

### 실패 시 확인 순서

1. EC2 종료와 ENI 제거가 완료됐는지 확인한다.
2. Route Table의 Subnet 연결이 해제됐는지 확인한다.
3. IGW가 VPC에서 분리됐는지 확인한다.
4. VPC 안에 남은 ENI, SG, Subnet이 없는지 확인한다.
5. IAM 사용자는 AWS 리소스를 전부 삭제한 뒤 마지막에 삭제한다.

---

## 로그 보안 최종 점검

로그를 Git에 추가하기 전에 다음 문자열을 검사한다.

```bash
rg -n \
  'AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|aws_secret_access_key|AWS_SECRET_ACCESS_KEY|AWS_SESSION_TOKEN' \
  docs/evidence/logs
```

검색 결과가 실제 비밀값을 포함하면 해당 로그를 커밋하지 말고 폐기한 뒤 제한된 쿼리로 다시 생성한다.
