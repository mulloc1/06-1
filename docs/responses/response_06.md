# 질문 06 — 외부에서 EC2까지의 네트워크 흐름

## 질문

`외부 → IGW → Subnet → EC2`로 이어지는 네트워크 흐름을 다이어그램 기준으로 설명할 수 있는가?

## 답변

외부 클라이언트가 EC2의 Public IPv4와 TCP 80으로 요청하면 흐름은 다음과 같다.

1. 인터넷의 클라이언트가 EC2 Public IPv4로 HTTP 요청을 보낸다.
2. VPC에 연결된 Internet Gateway가 인터넷과 VPC 사이의 통신 경로를 제공한다.
3. Public Subnet과 연결된 Route Table에는 `0.0.0.0/0 → IGW` 경로가 있어 외부와
   왕복할 수 있다.
4. EC2에 연결된 Security Group이 TCP 80, 소스 `0.0.0.0/0`인 요청만 허용한다.
5. 허용된 패킷이 EC2의 Nginx 80번 포트에 도달하고 `/health`에서 `OK`를 반환한다.
6. Security Group은 상태 저장 방식이므로 응답은 요청에 대한 반환 트래픽으로 허용되고,
   Route Table과 IGW를 통해 클라이언트로 돌아간다.

Subnet 자체가 트래픽을 처리하는 장비는 아니다. EC2가 들어가는 주소 범위와 Route Table
연결 경계를 제공하며, 실제 인터넷 경로는 IGW와 기본 경로, 접근 허용은 Security Group이
각각 담당한다.

## 실습 근거

- [아키텍처 다이어그램](../architecture.png)
- [네트워크 상태 로그](../evidence/logs/02-network-state.log)
- [외부 접속 로그](../evidence/logs/05-external-health.log)

