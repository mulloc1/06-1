# Command Log Index — 06-1 Cloud Lab

이 문서는 실행 로그의 색인과 합격 여부를 기록한다. 원본 출력 전체는 `docs/evidence/logs/`에 두며 이 문서에 중복 복사하지 않는다.

## 기록 원칙

- 실행 시각은 UTC ISO 8601 형식으로 기록한다.
- 기대 결과와 실제 결과를 비교해 `PASS` 또는 `FAIL`로 판정한다.
- 실패한 단계는 원인을 해결한 뒤 새 로그에 재실행하고 기존 실패 로그도 트러블슈팅 근거로 보존한다.
- Access Key, Secret Key, Session Token, MFA 코드, SSH Private Key는 어느 로그에도 기록하지 않는다.
- 외부 접속 필수 스크린샷은 사용자가 `docs/evidence/01-external-health.png`로 추가한다.

## 실행 로그 색인

| 단계 | 실행 시각(UTC) | 원본 로그 | 기대 결과 | 실제 결과 | 판정 |
| --- | --- | --- | --- | --- | --- |
| AWS CLI 버전 | 실행 후 기록 | `evidence/logs/00-cli-version.log` | AWS CLI v2 | 실행 전 | PENDING |
| IAM 검증 | 실행 후 기록 | `evidence/logs/01-iam-validation.log` | 호출자 일치, EC2 허용, S3/IAM 거부 | 실행 전 | PENDING |
| 네트워크 | 실행 후 기록 | `evidence/logs/02-network-state.log` | VPC/Subnet/IGW/Route 정상 | 실행 전 | PENDING |
| 네트워크 최종 검증 | 실행 후 기록 | `evidence/logs/02-network-validation.log` | 12개 검사와 종합 판정 PASS | 실행 전 | PENDING |
| Security Group | 실행 후 기록 | `evidence/logs/03-security-group.log` | HTTP 80 전체, SSH 22 `/32`만 허용 | 실행 전 | PENDING |
| EC2 및 Nginx | 실행 후 기록 | `evidence/logs/04-ec2-web-server.log` | 인스턴스 정상, localhost 200, outbound 성공 | 실행 전 | PENDING |
| SSH 접속 | 실행 후 기록 | `evidence/logs/04-ssh-connection.log` | `ec2-user` 원격 접속 성공 | 실행 전 | PENDING |
| 외부 접속 | 실행 후 기록 | `evidence/logs/05-external-health.log` | `/health` 200 및 `OK` | 실행 전 | PENDING |
| 외부 HTTP 200 판정 | 실행 후 기록 | `evidence/logs/05-http-200-ok.log` | 상태 코드 200, 본문 `OK`, 종합 판정 PASS | 실행 전 | PENDING |
| 장애 재현 | 실행 후 기록 | `evidence/logs/06-troubleshooting-before.log` | 외부 실패, localhost 성공 | 실행 전 | PENDING |
| 장애 복구 | 실행 후 기록 | `evidence/logs/07-troubleshooting-after.log` | SG 복구, 외부 200 | 실행 전 | PENDING |
| 정리 전 목록 | 실행 후 기록 | `evidence/logs/08-cleanup-before.log` | 삭제 대상 식별 | 실행 전 | PENDING |
| 정리 후 검증 | 실행 후 기록 | `evidence/logs/09-cleanup-after.log` | 모든 실습 리소스 조회 결과 없음 | 실행 전 | PENDING |

## 제출물 연결

| 제출물 | 경로 | 상태 |
| --- | --- | --- |
| 아키텍처 다이어그램 | `architecture.png` | 완료 |
| 외부 접속 스크린샷 | `evidence/01-external-health.png` | 사용자 추가 필요 |
| 명령 가이드 | `aws-cli-commands.md` | 완료 |
| 트러블슈팅 보고서 | `troubleshooting.md` | 실행 후 작성 |
| 정리 체크리스트 | `cleanup-checklist.md` | 템플릿 완료, 실행 후 체크 필요 |

## 커밋 전 보안 검사

```bash
rg -n \
  'AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|aws_secret_access_key|AWS_SECRET_ACCESS_KEY|AWS_SESSION_TOKEN' \
  docs/evidence/logs
```

실제 비밀값이 발견되면 해당 로그를 커밋하지 않고 폐기한 뒤 제한된 `--query`를 사용해 다시 생성한다.
