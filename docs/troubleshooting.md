# 트러블슈팅 보고서 — 외부 웹 접속 장애

## 1. 장애 상황

EC2에 설치한 Nginx는 실행 중이지만 외부 환경에서 다음 요청이 실패하는 상황을 대상으로 한다.

```bash
curl --connect-timeout 10 "http://${LAB_PUBLIC_IP}/health"
```

정상이라면 HTTP 상태 코드 `200`과 고정 본문 `OK`가 반환되어야 한다. 외부 요청이
타임아웃되거나 200 이외의 상태를 반환하면 아래 네 구간 중 하나에 문제가 있다고 가정한다.

```text
외부 사용자
  → Public IPv4
  → Internet Gateway와 Route Table
  → Security Group TCP 80
  → EC2 Nginx /health
```

## 2. 정상 상태 기준

장애 진단 전에 정상 상태를 다음과 같이 정의했다.

| 구간 | 정상 조건 | 증거 |
| --- | --- | --- |
| VPC | CIDR `10.0.0.0/16`, 상태 `available` | [네트워크 검증](evidence/logs/02-network-validation.log) |
| Public Subnet | CIDR `10.0.1.0/24`, Public IP 자동 할당 활성화 | [네트워크 검증](evidence/logs/02-network-validation.log) |
| IGW | 실습 VPC에 `available` 상태로 연결 | [네트워크 검증](evidence/logs/02-network-validation.log) |
| Route Table | `0.0.0.0/0 → IGW`가 `active`, Public Subnet 연결 | [네트워크 검증](evidence/logs/02-network-validation.log) |
| Security Group | TCP 80은 `0.0.0.0/0`, SSH 22는 학습자 IP `/32` | [Security Group 검증](evidence/logs/03-security-group.log) |
| EC2와 Nginx | EC2 `running`, Nginx `active`, localhost `/health` 200/OK | [서버 내부 검증](evidence/logs/04-ec2-web-server.log) |
| 외부 요청 | `/health` 상태 `200`, 본문 `OK` | [외부 접속 검증](evidence/logs/05-http-200-ok.log) |

저장된 외부 접속 검증 결과는 다음과 같다.

```text
http_status=200
response_body=OK
http_200_ok=PASS
```

## 3. 가설과 확인 순서

외부에서 안 된다는 이유만으로 여러 설정을 동시에 수정하면 어느 변경이 문제를 해결했는지
알 수 없다. 따라서 평가항목에서 제시한 순서대로 하나씩 확인한다.

```text
라우팅 → Security Group → Public IP/DNS → 서버 프로세스/로그
```

### 가설 1 — IGW 또는 Route Table이 잘못됐다

Public Subnet에 기본 인터넷 경로가 없거나 IGW가 VPC에 연결되지 않으면 외부 패킷이
EC2까지 도달할 수 없다.

#### 확인 명령

```bash
aws ec2 describe-internet-gateways \
  --internet-gateway-ids "$LAB_IGW_ID" \
  --query 'InternetGateways[0].Attachments[0].{VpcId:VpcId,State:State}' \
  --region "$AWS_REGION" \
  --no-cli-pager

aws ec2 describe-route-tables \
  --route-table-ids "$LAB_ROUTE_TABLE_ID" \
  --query 'RouteTables[0].{Routes:Routes,Associations:Associations}' \
  --region "$AWS_REGION" \
  --no-cli-pager
```

#### 정상 판정

- IGW의 연결 VPC가 `$LAB_VPC_ID`와 일치한다.
- IGW 연결 상태가 `available`이다.
- `0.0.0.0/0`의 대상이 `$LAB_IGW_ID`이고 상태가 `active`이다.
- `$LAB_SUBNET_ID`가 해당 Route Table에 연결되어 있다.

[네트워크 검증 로그](evidence/logs/02-network-validation.log)에서는 위 항목이 모두 PASS했다.

### 가설 2 — Security Group이 TCP 80을 차단한다

라우팅이 정상이어도 EC2의 Security Group에 HTTP 인바운드 규칙이 없으면 외부 요청은
EC2의 Nginx까지 전달되지 않는다.

#### 확인 명령

```bash
aws ec2 describe-security-groups \
  --group-ids "$LAB_SECURITY_GROUP_ID" \
  --query 'SecurityGroups[0].IpPermissions[].{Protocol:IpProtocol,From:FromPort,To:ToPort,CIDRs:IpRanges[].CidrIp}' \
  --region "$AWS_REGION" \
  --no-cli-pager
```

#### 정상 판정

- TCP 80의 소스가 `0.0.0.0/0`이다.
- SSH 22의 소스가 학습자 Public IPv4 `/32`이다.
- 과제에 필요하지 않은 다른 인바운드 포트는 없다.

외부 `/health`는 실패하지만 localhost `/health`가 성공한다면 Nginx보다 이 규칙과
라우팅을 우선 의심한다.

### 가설 3 — 이전 Public IPv4로 접속하고 있다

자동 할당 Public IPv4는 EC2 재생성 또는 중지·시작 후 변경될 수 있다. `.env`, 브라우저,
`curl` 또는 SSH에서 이전 주소를 사용하면 정상 인스턴스에 도달하지 않는다.

#### 확인 명령

```bash
aws ec2 describe-instances \
  --instance-ids "$LAB_INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].{State:State.Name,PublicIp:PublicIpAddress,SubnetId:SubnetId,SecurityGroups:SecurityGroups[].GroupId}' \
  --region "$AWS_REGION" \
  --no-cli-pager
```

#### 정상 판정

- 인스턴스 상태가 `running`이다.
- 현재 Public IPv4가 존재한다.
- Subnet과 Security Group ID가 실습 리소스 ID와 일치한다.
- 실제 Public IPv4와 요청 대상 주소가 일치한다.

### 가설 4 — Nginx 또는 `/health` 설정이 잘못됐다

네트워크 경로가 정상이어도 Nginx가 중지됐거나 `/health` 파일과 설정에 문제가 있으면
외부 요청에 정상 응답할 수 없다.

#### 확인 명령

```bash
ssh -i ".secrets/${LAB_KEY_NAME}.pem" \
  "ec2-user@${LAB_PUBLIC_IP}" \
  "systemctl is-active nginx; curl -i http://localhost/health"
```

#### 정상 판정

- `systemctl is-active nginx` 결과가 `active`이다.
- localhost `/health`의 상태 코드가 `200`이다.
- 응답 본문이 정확히 `OK`이다.

localhost부터 실패한다면 SG를 수정하기 전에 Nginx 상태와 설정을 확인한다.

```bash
sudo systemctl status nginx
sudo journalctl -u nginx --no-pager
sudo nginx -t
sudo tail -n 100 /var/log/nginx/error.log
```

## 4. 관측 결과에 따른 원인 판정

| 외부 `/health` | localhost `/health` | SSH | 우선 의심할 원인 |
| --- | --- | --- | --- |
| 실패 | 200/OK | 성공 | SG TCP 80, Route Table, IGW, 잘못된 Public IP |
| 실패 | 실패 | 성공 | Nginx 프로세스, `/health` 설정, 80 포트 리스닝 |
| 실패 | 확인 불가 | 실패 | SSH `/32`, Public IP, 라우팅, EC2 상태 |
| 200/OK | 200/OK | 성공 | 외부 경로와 서버가 정상 |

이 실습의 저장된 로그에서는 라우팅 검증이 PASS했고, TCP 80 규칙이 존재했으며,
Nginx와 localhost `/health`도 정상이었다. 최종 외부 요청 역시 200/OK였다.

## 5. Security Group 장애 재현 및 복구 절차

Security Group이 외부 접속에 미치는 영향을 확인해야 한다면 TCP 80 규칙만 통제해서
변경한다. Route Table, Public IP와 Nginx는 동시에 수정하지 않는다.

### 5.1 변경 전 기준 상태

```bash
curl --include --connect-timeout 10 \
  "http://${LAB_PUBLIC_IP}/health"
```

기대 결과는 외부 HTTP 200과 본문 `OK`이다.

### 5.2 TCP 80 규칙 제거

```bash
aws ec2 revoke-security-group-ingress \
  --group-id "$LAB_SECURITY_GROUP_ID" \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0 \
  --region "$AWS_REGION" \
  --no-cli-pager
```

규칙 제거 후에는 다음 결과를 비교한다.

- 외부 Public IPv4의 `/health`: 연결 실패 또는 시간 초과
- EC2 내부 localhost `/health`: HTTP 200과 본문 `OK`

두 결과가 이렇게 갈리면 Nginx가 아니라 외부 인바운드를 제어하는 Security Group이
장애 원인이라는 가설이 지지된다.

### 5.3 TCP 80 규칙 복구

```bash
aws ec2 authorize-security-group-ingress \
  --group-id "$LAB_SECURITY_GROUP_ID" \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0 \
  --region "$AWS_REGION" \
  --no-cli-pager
```

### 5.4 복구 후 재검증

```bash
curl --silent --show-error \
  --output /tmp/lab-health-body \
  --write-out 'http_status=%{http_code}\n' \
  "http://${LAB_PUBLIC_IP}/health"

printf 'response_body='
tr -d '\r\n' < /tmp/lab-health-body
printf '\n'
```

복구 완료 기준은 다음과 같다.

```text
http_status=200
response_body=OK
```

## 6. 가설 → 검증 순서를 유지하는 이유

라우팅, SG와 Nginx를 한꺼번에 변경하면 어떤 변경이 문제를 해결했는지 알 수 없다.
먼저 한 문장으로 가설을 세우고 그 가설만 판별할 수 있는 명령을 실행하면 다음 장점이 있다.

- 장애 범위를 빠르게 좁힐 수 있다.
- 정상 설정을 불필요하게 변경하지 않는다.
- 원인과 복구 조치 사이의 관계를 설명할 수 있다.
- UTC 실행 시각, 명령, 출력과 종료 코드를 근거로 남길 수 있다.
- 실패 결과도 삭제하지 않고 다음 판단의 근거로 사용할 수 있다.

따라서 외부 웹 접속 장애는 다음 순서로 진단한다.

```text
라우팅 확인
  → Security Group 확인
  → 현재 Public IPv4 확인
  → Nginx와 localhost 확인
  → 외부 /health 재검증
```

## 7. 증거 범위

실제로 저장된 로그는 정상 구성과 외부 HTTP 200 상태를 증명한다. 리소스 정리 전에
TCP 80 제거·복구 실험은 실행하지 않았으므로 예상되는 장애 결과를 실제 로그로 표시하지 않는다.

- [네트워크 검증](evidence/logs/02-network-validation.log)
- [Security Group 검증](evidence/logs/03-security-group.log)
- [EC2·Nginx·localhost 검증](evidence/logs/04-ec2-web-server.log)
- [외부 접속 응답](evidence/logs/05-external-health.log)
- [외부 HTTP 200 판정](evidence/logs/05-http-200-ok.log)
