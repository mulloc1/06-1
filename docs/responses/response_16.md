# 질문 16 — EC2 2대로 확장할 때의 병목과 구성

## 질문

트래픽이 늘어 인스턴스를 2대로 늘리면 현재 구조에서 무엇이 병목이고 어떤 구성요소를 추가해야 하는가?

## 답변

현재는 하나의 Public IPv4가 하나의 EC2와 Nginx에 직접 연결된다. EC2를 단순히 한 대 더
생성해도 사용자가 어느 인스턴스로 접근해야 하는지 자동 분산되지 않고, 한 인스턴스가
고장 나면 그 IP로 들어오는 요청은 계속 실패한다. 배포와 상태 확인도 인스턴스마다 따로
관리해야 한다.

두 대로 확장할 때는 다음 구조로 바꾼다.

1. 최소 두 Availability Zone에 Public Subnet을 만든다.
2. 인터넷 요청을 받는 Application Load Balancer(ALB)를 Public Subnet에 배치한다.
3. EC2 두 대를 Target Group에 등록한다.
4. ALB가 `/health`를 호출해 정상 인스턴스에만 트래픽을 전달하게 한다.
5. ALB Security Group은 80/443을 외부에 허용하고, EC2 Security Group은 HTTP 소스를
   ALB Security Group으로만 제한한다.
6. Launch Template과 Auto Scaling Group을 사용해 최소·희망·최대 용량을 관리한다.
7. DNS가 필요하면 Route 53 레코드를 ALB에 연결하고 ACM 인증서로 HTTPS를 종료한다.

애플리케이션이 상태를 로컬 디스크에 저장한다면 인스턴스 간 데이터 불일치가 다음 병목이
된다. 세션은 외부 저장소로 옮기고, 공유 파일은 S3/EFS, 데이터는 관리형 DB 등으로 분리해
EC2를 교체 가능한 무상태 서버로 만드는 것이 좋다.

## 현재 구조 기준 근거

- [단일 EC2 구조 다이어그램](../architecture.png)
- 현재 `/health`가 있으므로 ALB Target Group의 Health Check 경로로 재사용할 수 있다.

