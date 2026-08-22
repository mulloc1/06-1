# 질문 04 — 외부 접속 검증

## 질문

외부 접속이 브라우저 또는 `GET /health` 방식 중 하나로 검증되는가?

## 답변

방법 **B — `GET /health`**를 선택했다. 로컬 컴퓨터에서 EC2의 Public IPv4를 대상으로
다음 요청을 실행했다.

```bash
curl --include http://13.125.220.199/health
```

실제 응답은 HTTP `200 OK`, 고정 본문 `OK`, 종료 코드 `0`이었다. 이 검증은 EC2 내부의
localhost 요청이 아니라 외부 네트워크에서 Public IPv4로 보낸 요청이므로 IGW, Route Table,
Public IP, Security Group 80번 규칙, Nginx가 모두 정상이어야 성공한다.

## 실습 근거

- [외부 `/health` 원본 로그](../evidence/logs/05-external-health.log)
- [README의 선택 방식과 URL](../../README.md)

EC2 재생성 시 Public IPv4가 바뀔 수 있으므로 제출 시에는 실습 당시 URL과 원본 로그를
함께 제시한다.

