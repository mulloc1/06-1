# 질문 02 — EC2 SSH 접속과 웹 서버 실행

## 질문

EC2에 SSH로 접속 가능하며, 웹 서버가 실행 중인가?

## 답변

Amazon Linux 2023 AMI와 `t3.micro` 인스턴스를 Public Subnet에 생성했다. 루트 볼륨은
암호화된 8GiB `gp3`이며 인스턴스 종료 시 함께 삭제되도록 설정했다.

ED25519 Key Pair를 사용해 `ec2-user`로 SSH 접속했고, user data로 Nginx를 설치해
자동 시작하도록 구성했다. SSH 접속 후 다음 항목을 검증했다.

- `systemctl is-active nginx` → `active`
- `curl http://localhost/` → HTTP `200`
- `curl http://localhost/health` → HTTP `200`, 본문 `OK`
- 인스턴스에서 `https://example.com`으로 아웃바운드 접속 → 성공

Private Key는 `.secrets/`에 권한 `600`으로 저장하고 Git에서 제외했다. 로그에는 키
본문을 남기지 않고 `<protected-key>`로 표시했다.

## 실습 근거

- [EC2·EBS·SSH·Nginx 검증 로그](../evidence/logs/04-ec2-web-server.log)
- [Nginx 설치용 user data](../../infra/user-data.sh)

