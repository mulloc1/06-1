# Cloud Infrastructure & Web Service Deployment

서울 리전(`ap-northeast-2`)에 VPC, Public Subnet, Internet Gateway, Route Table,
Security Group, EC2와 Nginx를 구성하는 실습 프로젝트다.

## 사전 준비

- AWS CLI v2
- `lab-cloud-web` IAM 사용자
- 저장소의 `docs/iam/lab-cloud-web-policy.template.json` 정책
- IAM Access Key와 가상 MFA 장치

AWS CLI 설치와 IAM 사용자·정책 생성은 자동화 대상에 포함하지 않는다. 장기 자격 증명은
명령 인자로 전달하거나 로그에 남기지 않고 로컬 `.env`에서만 관리한다.

## 빠른 실행

저장소 루트에서 아래 두 파일을 순서대로 실행한다.

```bash
./scripts/setup-aws-cli.sh
./scripts/setup-server.sh
```

### 1. AWS CLI 연동

`setup-aws-cli.sh`가 수행하는 작업:

- `.env`가 없으면 `.env.example`을 복사하고 권한을 `600`으로 설정
- 누락된 Access Key, Secret Access Key, MFA 장치 ARN을 화면에 노출하지 않고 입력
- MFA 6자리 코드로 12시간 임시 세션 발급
- 임시 자격 증명을 로컬 `.env`에 저장
- 호출자가 `lab-cloud-web`인지 Boolean 결과로 검증

세션이 만료됐을 때는 같은 파일을 다시 실행하면 된다. 기존 네트워크와 EC2 ID는
덮어쓰지 않는다.

### 2. 서버 설정

`setup-server.sh`가 다음 작업을 순서대로 수행한다.

1. AWS 세션과 서울 리전 확인
2. VPC `10.0.0.0/16`
3. Public Subnet `10.0.1.0/24`
4. Internet Gateway 및 `0.0.0.0/0` 기본 경로
5. HTTP 80 전체 허용, SSH 22 학습자 IP `/32` Security Group
6. ED25519 Key Pair
7. Amazon Linux 2023 `t3.micro`, 암호화된 8GiB gp3
8. Nginx와 `/health` 배포
9. SSH, localhost, 인스턴스 아웃바운드, 외부 `/health` 검증

모든 AWS 리소스에는 `Project=codyssey-06-1` 태그를 사용한다. 같은 태그와 이름의
리소스가 이미 있으면 재사용하므로 다시 실행해도 중복 생성을 피한다.

화면 캡처와 HTTP 규칙 제거를 이용한 장애 재현은 자동 서버 설정에 포함하지 않는다.

실행 증거는 `docs/evidence/logs/`에 누적되며, SSH 접속 성공은
`04-ssh-connection.log`, 외부 `/health`의 상태 코드·본문 판정은
`05-http-200-ok.log`에서 각각 독립적으로 확인할 수 있다. SSH Private Key 내용은 로그에
기록하지 않는다.

### 3. 네트워크 최종 검증

서버 구성 후 VPC, Public Subnet, IGW와 Route Table을 변경 없이 다시 검증한다.

```bash
./scripts/verify-network.sh
```

스크립트가 `.env`를 자동으로 불러오므로 환경 변수를 수동으로 `source`할 필요가 없다.
VPC CIDR·상태·태그, Subnet CIDR·Public IPv4 자동 할당, IGW 연결, local·기본 경로와
Subnet 연결을 판정하고 결과를 아래 파일에 저장한다.

```text
docs/evidence/logs/02-network-validation.log
```

마지막 줄이 `NETWORK_VALIDATION=PASS`이면 네트워크 평가 조건을 모두 충족한 것이다.

## 외부 접속 검증

- 선택 방법: **B — `GET /health`**
- 실습 당시 URL: `http://13.125.220.199/health`
- 결과: HTTP `200 OK`, 본문 `OK`
- 원본 로그: `docs/evidence/logs/05-external-health.log`
- 자동 판정 로그: `docs/evidence/logs/05-http-200-ok.log`

EC2를 종료하고 다시 생성하면 Public IPv4가 달라질 수 있다. 현재 주소는 `.env`의
`LAB_PUBLIC_IP` 또는 `setup-server.sh`의 완료 출력에서 확인한다.

## 리소스 정리

필수 증거를 모두 확보한 뒤 먼저 조회 전용 모드로 삭제 대상을 확인한다.

```bash
./scripts/cleanup-server.sh
```

실제 삭제는 `execute`를 명시하고 화면에 프로젝트명 `codyssey-06-1`을 다시 입력해야
시작된다.

```bash
./scripts/cleanup-server.sh execute
```

`./scripts/cleanup-server.sh --execute`도 동일하게 동작한다.

실행 모드는 삭제 전 상태와 명령을 `docs/evidence/logs/08-cleanup-before.log`에,
프로젝트 리소스가 모두 0개인지 확인한 결과를 `09-cleanup-after.log`에 기록한다.

이 스크립트는 AWS의 EC2·EBS·Key Pair·SG·Route Table·Subnet·IGW·VPC와 해당 AWS
Key Pair에 대응하는 로컬 Private Key를 삭제한다. 삭제 후 조회에 필요한 IAM 사용자,
Access Key, MFA와 `.env`는 보존하며 최종 검증 후 별도로 정리한다.

## 주요 제출물

- 아키텍처: `docs/architecture.png`
- 전체 명령 가이드: `docs/aws-cli-commands.md`
- 실행 로그 색인: `docs/command-log.md`
- 정리 체크리스트: `docs/cleanup-checklist.md`
- 실행 로그: `docs/evidence/logs/`

`.env`, SSH Private Key와 MFA 임시 토큰은 Git에 포함하지 않는다.
