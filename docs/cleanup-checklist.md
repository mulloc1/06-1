# Cleanup Checklist — 06-1 Cloud Lab

> Region: `ap-northeast-2`. 모든 접속·트러블슈팅 증거를 수집한 뒤 실행한다.
> 종속 리소스를 먼저 제거하고, 삭제 결과는 `docs/evidence/logs/09-cleanup-after.log`로 증명한다.

## 안전한 실행 방법

먼저 조회 전용 모드로 대상 ID와 `Project=codyssey-06-1` 태그를 확인한다. 이 명령은 AWS
리소스와 로그 파일을 변경하지 않는다.

```bash
./scripts/cleanup-server.sh
```

실제 삭제는 아래 명령을 실행한 뒤 확인 문구 `codyssey-06-1`을 직접 입력해야 시작된다.

```bash
./scripts/cleanup-server.sh execute
```

`./scripts/cleanup-server.sh --execute`도 동일하게 동작한다.

실행 모드는 `08-cleanup-before.log`와 `09-cleanup-after.log`를 자동 생성하고 AWS Key Pair와
대응하는 로컬 Private Key를 함께 삭제한다. IAM 사용자와 정책, MFA, Access Key와 로컬
`.env`는 삭제 후 AWS 조회를 마친 다음 별도로 정리한다.

## 정리 전 확인

- [ ] 외부 `/health` 200 로그를 저장했다.
- [ ] 사용자가 필수 외부 접속 스크린샷을 추가했다.
- [ ] 트러블슈팅 전후 로그를 저장했다.
- [ ] `docs/evidence/logs/08-cleanup-before.log`에 삭제 대상 ID를 기록했다.
- [ ] `.env`에 EC2, EBS, VPC, Subnet, IGW, Route Table, SG ID가 남아 있다.

## 리소스 정리 순서

| # | 확인 | 리소스 | 식별자 | 작업 | 완료 증거 |
| --- | --- | --- | --- | --- | --- |
| 1 | [ ] | EC2 | `LAB_INSTANCE_ID` | 종료 후 `instance-terminated`까지 대기 | `09-cleanup-after.log`의 활성 인스턴스 빈 목록 |
| 2 | [ ] | EBS | `LAB_VOLUME_ID` | `DeleteOnTermination=true` 자동 삭제 확인 | `09-cleanup-after.log`의 볼륨 빈 목록 |
| 3 | [ ] | Public IPv4 | `LAB_PUBLIC_IP` | EC2 종료와 함께 해제 확인 | 활성 인스턴스 빈 목록 |
| 4 | [ ] | Elastic IP | Core scope에서 생성하지 않음 | 프로젝트 태그 EIP가 없는지 확인 | `09-cleanup-after.log`의 EIP 빈 목록 |
| 5 | [ ] | Key Pair | `LAB_KEY_NAME` | AWS Key Pair 삭제 | `09-cleanup-after.log`의 Key Pair 빈 목록 |
| 6 | [ ] | Security Group | `LAB_SECURITY_GROUP_ID` | EC2 ENI 제거 후 삭제 | `09-cleanup-after.log`의 SG 빈 목록 |
| 7 | [ ] | Route Table 연결 | `LAB_ROUTE_ASSOCIATION_ID` | Public Subnet 연결 해제 | 삭제 명령 성공 |
| 8 | [ ] | Route Table | `LAB_ROUTE_TABLE_ID` | 사용자 정의 Route Table 삭제 | `09-cleanup-after.log`의 Route Table 빈 목록 |
| 9 | [ ] | Public Subnet | `LAB_SUBNET_ID` | 삭제 | `09-cleanup-after.log`의 Subnet 빈 목록 |
| 10 | [ ] | Internet Gateway | `LAB_IGW_ID` | VPC에서 분리 후 삭제 | `09-cleanup-after.log`의 IGW 빈 목록 |
| 11 | [ ] | VPC | `LAB_VPC_ID` | 마지막 네트워크 리소스로 삭제 | `09-cleanup-after.log`의 VPC 빈 목록 |
| 12 | [ ] | IAM Access Key | `lab-cloud-web` | 비활성화 후 삭제 | 관리자 Console 확인 |
| 13 | [ ] | Virtual MFA | `AWS_MFA_SERIAL` | 사용자에서 해제 후 삭제 | 관리자 Console 확인 |
| 14 | [ ] | IAM 사용자 | `lab-cloud-web` | 정책 분리 후 삭제 | 관리자 Console 확인 |
| 15 | [ ] | IAM 정책 | `lab-cloud-web-policy` | 연결 해제 후 삭제 | 관리자 Console 확인 |
| 16 | [ ] | SSH Private Key | `.secrets/lab-cloud-web-key.pem` | 정리 스크립트에서 AWS Key Pair와 함께 삭제 | 로컬 파일 없음 |
| 17 | [ ] | 로컬 환경 파일 | `.env` | IAM 키 폐기 후 삭제 | `.env` 없음 |

## 삭제 후 검증

다음 항목은 모두 빈 목록이어야 한다. 자동화는 `scripts/cleanup-server.sh --execute`, 개별
명령 확인은 `docs/aws-cli-commands.md` Step 10을 사용한다.

- [ ] 실행 중이거나 중지된 프로젝트 EC2가 없다.
- [ ] 프로젝트 EBS 볼륨이 없다.
- [ ] 프로젝트 Elastic IP가 없다.
- [ ] 프로젝트 Security Group이 없다.
- [ ] 프로젝트 Key Pair가 없다.
- [ ] 프로젝트 Route Table과 Subnet이 없다.
- [ ] 프로젝트 Internet Gateway가 없다.
- [ ] 프로젝트 VPC가 없다.
- [ ] `lab-cloud-web` IAM 사용자와 Access Key가 없다.
- [ ] `lab-cloud-web-policy`가 없다.
- [ ] 다른 리전에 `lab-cloud-web-*` 리소스가 없는지 관리자 Console에서 확인했다.
- [ ] Billing 또는 Cost Explorer의 반영 지연 가능성을 기록했다.

## 최종 상태 기록

| 항목 | 값 |
| --- | --- |
| 정리 실행 일시(UTC) | 실행 후 기록 |
| 정리 리전 | `ap-northeast-2` |
| 검증 로그 | `docs/evidence/logs/09-cleanup-after.log` |
| EIP 생성 여부 | 생성하지 않음 |
| IAM 최종 상태 | 실행 후 기록 |
| Billing 확인 일시 | 실행 후 기록 |
