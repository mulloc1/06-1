# 질문 08 — 외부 접속 검증 방식 선택과 구성

## 질문

외부 접속 검증을 (A) 또는 (B) 중 무엇으로 선택했고, 이를 위해 무엇을 어떻게 구성했는가?

## 답변

자동화와 재현성이 좋은 **B — `GET /health`** 방식을 선택했다. 브라우저 화면은 사람이
확인하기 쉽지만 결과 판정이 주관적일 수 있다. `/health`는 상태 코드, 고정 본문, 종료 코드를
텍스트 로그로 남길 수 있어 실행 시각과 성공 여부를 다시 검토하기 쉽다.

이를 위해 다음을 구성했다.

1. Public Subnet에 EC2를 배치하고 Public IPv4를 할당했다.
2. VPC에 IGW를 연결하고 Public Subnet Route Table에 `0.0.0.0/0 → IGW`를 추가했다.
3. Security Group에서 TCP 80을 `0.0.0.0/0`에 허용했다.
4. user data로 Nginx를 설치하고 `/usr/share/nginx/html/health`에 `OK`를 기록했다.
5. Nginx를 활성화한 뒤 내부 localhost와 외부 Public IPv4에서 각각 검증했다.
6. 외부 응답 전체와 종료 코드를 로그로 보존했다.

## 실습 근거

- [Nginx user data](../../infra/user-data.sh)
- [외부 `/health` 응답 로그](../evidence/logs/05-external-health.log)
- [README 외부 접속 검증](../../README.md)

