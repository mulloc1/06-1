# 질문 11 — Security Group과 IAM의 책임 범위

## 질문

Security Group과 IAM의 책임 범위 차이와 최소 권한이 필요한 이유는 무엇인가?

## 답변

Security Group은 **네트워크 트래픽**, IAM은 **AWS API 작업 권한**을 제어한다.

| 구분 | Security Group | IAM |
| --- | --- | --- |
| 질문 | 어떤 네트워크 연결을 허용하는가? | 누가 어떤 AWS 작업을 할 수 있는가? |
| 대상 | EC2 ENI로 들어오고 나가는 패킷 | 사용자·역할이 호출하는 AWS API |
| 예시 | TCP 80 공개, SSH 22를 `/32`로 제한 | VPC·EC2 생성 허용, S3·IAM 관리 거부 |
| 영향 | 서비스 포트 접근 가능 여부 | 리소스 조회·생성·수정·삭제 가능 여부 |

예를 들어 IAM에 `RunInstances` 권한이 있어도 Security Group이 TCP 80을 막으면 외부에서
웹 페이지에 접근할 수 없다. 반대로 TCP 80이 열려 있어도 IAM 권한이 없으면 사용자가
보안 그룹이나 EC2 설정을 변경할 수 없다.

최소 권한은 계정이나 자격 증명이 오용됐을 때 피해 범위를 줄인다. 이번 IAM 정책은
AdministratorAccess 대신 EC2/VPC/SG 실습 동작만 허용하고, MFA가 존재하며 서울 리전인
경우에만 적용했다. S3, RDS, IAM 관리와 CloudWatch/AWS Health 같은 과제 외 권한은
부여하지 않았다.

## 실습 근거

- [IAM 최소 권한 정책](../iam/lab-cloud-web-policy.template.json)
- [Security Group 규칙 로그](../evidence/logs/03-security-group.log)

