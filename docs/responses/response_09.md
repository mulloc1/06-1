# 질문 09 — 리소스 추적과 정리 기준

## 질문

실습 리소스를 추적·정리하기 위해 어떤 태그, 이름 규칙, 체크리스트를 사용했는가?

## 답변

모든 생성 가능 리소스에 공통 태그 `Project=codyssey-06-1`을 사용했다. 이름은
`lab-cloud-web` 접두어 뒤에 역할을 붙였다.

| 리소스 | 이름 예시 |
| --- | --- |
| VPC | `lab-cloud-web-vpc` |
| Public Subnet | `lab-cloud-web-public-subnet` |
| Internet Gateway | `lab-cloud-web-igw` |
| Route Table | `lab-cloud-web-public-rt` |
| Security Group | `lab-cloud-web-sg` |
| EC2 | `lab-cloud-web-ec2` |
| Key Pair | `lab-cloud-web-key` |

자동화 스크립트는 태그와 이름을 함께 조회해 기존 리소스를 재사용하므로 중복 생성을 막는다.
생성된 VPC, Subnet, IGW, Route Table, 연결, SG, EC2, EBS와 Public IPv4 ID는 로컬
`.env`의 `LAB_*` 변수에 기록한다.

정리할 때는 `.env`의 정확한 ID, 프로젝트 태그 조회 결과와
`docs/cleanup-checklist.md`를 함께 사용한다. 삭제 전·후 상태를 별도 로그로 남겨
“삭제 명령을 실행했다”가 아니라 “대상이 더 이상 조회되지 않는다”를 완료 기준으로 삼는다.

## 실습 근거

- [네트워크 태그 및 ID 로그](../evidence/logs/02-network-state.log)
- [정리 체크리스트](../cleanup-checklist.md)
- [자동 실행 안내](../../README.md)

