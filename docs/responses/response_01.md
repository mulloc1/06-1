# 질문 01 — 네트워크 구성 검증

## 질문

VPC, Public Subnet, Internet Gateway, Route Table(`0.0.0.0/0` → IGW)이 구성되어 있는가?

## 답변

서울 리전 `ap-northeast-2`에 다음과 같이 구성했다.

| 구성요소 | 설정 |
| --- | --- |
| VPC | `10.0.0.0/16`, DNS support/hostnames 활성화 |
| Public Subnet | `10.0.1.0/24`, `ap-northeast-2a`, Public IPv4 자동 할당 |
| Internet Gateway | VPC에 연결된 상태 |
| Route Table | VPC 내부 통신용 `10.0.0.0/16 → local` |
| 기본 경로 | 외부 통신용 `0.0.0.0/0 → IGW` |
| Subnet 연결 | Public Subnet을 사용자 정의 Route Table에 연결 |

서브넷에 이름만 `public`이라고 붙인 것이 아니라 Public IPv4 자동 할당, IGW 연결,
기본 경로, Route Table 연결까지 함께 구성했기 때문에 실제 Public Subnet으로 동작한다.

## 실습 근거

- [네트워크 생성·조회 로그](../evidence/logs/02-network-state.log)
- `../evidence/logs/02-network-validation.log` — `verify-network.sh` 실행 후 생성되는 최종 판정 로그
- [아키텍처 다이어그램](../architecture.png)

로그에서 VPC와 Subnet CIDR, IGW의 `available` 연결 상태, `local` 경로와
`0.0.0.0/0 → IGW` 경로가 모두 `active`임을 확인할 수 있다.
