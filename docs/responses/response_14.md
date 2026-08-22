# 질문 14 — 외부 접속 장애 점검 순서

## 질문

외부 접속이 안 될 때 어떤 순서로 점검하는가?

## 답변

넓은 네트워크 경계에서 인스턴스 내부로 좁혀 가며 다음 순서로 점검한다.

### 1. 라우팅

- IGW가 올바른 VPC에 `available` 상태로 연결됐는가?
- Public Subnet Route Table에 `0.0.0.0/0 → IGW`가 `active`인가?
- 해당 Subnet이 그 Route Table에 연결됐는가?

### 2. Security Group

- EC2에 올바른 SG가 연결됐는가?
- TCP 80의 소스가 `0.0.0.0/0`인가?
- SSH 22는 학습자 IP `/32`인가?

### 3. Public IP와 주소

- 인스턴스가 `running`이며 상태 검사를 통과했는가?
- Public IPv4가 실제로 할당됐는가?
- 재생성 후 예전 IP나 잘못된 DNS를 사용하고 있지 않은가?

### 4. 서버 프로세스와 로그

- SSH 접속이 되는가?
- `systemctl is-active nginx`가 `active`인가?
- `curl http://localhost/health`가 `200/OK`인가?
- `journalctl -u nginx`, Nginx 로그와 user data 로그에 오류가 있는가?

localhost가 성공하고 외부만 실패하면 Nginx보다 라우팅·Public IP·SG를 우선 의심한다.
반대로 localhost부터 실패하면 서비스 프로세스, 포트 리스닝, 설정과 로그를 먼저 수정한다.

## 실습 근거

- [네트워크 상태 로그](../evidence/logs/02-network-state.log)
- [SG 제거 시 외부 실패·localhost 성공 로그](../evidence/logs/06-troubleshooting-before.log)

