# 질문 10 — Public Subnet 기본 경로의 필요성

## 질문

Public Subnet Route Table의 기본 경로(`0.0.0.0/0` → IGW)가 필요한 이유는 무엇인가?

## 답변

Route Table은 목적지 주소에 따라 패킷을 어디로 보낼지 결정한다. VPC를 생성하면
`10.0.0.0/16 → local` 경로는 자동으로 생기지만, 이 경로는 VPC 내부 주소 사이의 통신만
처리한다. 인터넷 목적지는 `10.0.0.0/16`에 포함되지 않으므로 별도 경로가 없으면 패킷을
외부로 보낼 수 없다.

`0.0.0.0/0`은 더 구체적인 경로와 일치하지 않는 모든 IPv4 목적지를 뜻한다. 이를 IGW로
지정하면 다음 통신이 가능해진다.

- 외부 클라이언트가 EC2 Public IPv4의 Nginx로 접근
- EC2가 패키지 저장소에서 Nginx를 설치
- EC2가 외부 사이트로 아웃바운드 요청

다만 기본 경로만 추가한다고 Public Subnet이 완성되는 것은 아니다. IGW가 VPC에 연결되어
있어야 하고, Subnet이 해당 Route Table과 연결되어야 하며, EC2에 Public IPv4가 있어야
한다. 마지막으로 Security Group이 필요한 포트를 허용해야 실제 요청이 도달한다.

## 실습 근거

- [Route Table의 local·기본 경로 로그](../evidence/logs/02-network-state.log)
- [인스턴스 아웃바운드 성공 로그](../evidence/logs/04-ec2-web-server.log)

