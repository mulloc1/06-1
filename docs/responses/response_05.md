# 질문 05 — 리소스 정리 완료 확인

## 질문

리소스 정리 체크리스트에서 최소 5종(`EC2` / `EBS` / `EIP` / `IGW` / `VPC`) 정리 완료를 확인할 수 있는가?

## 현재 답변

아직 외부 접속 증거와 문서 정리 단계이므로 AWS 리소스 삭제는 수행하지 않았다. 따라서
이 문항의 현재 판정은 **PENDING**이며 완료된 것처럼 제출하면 안 된다.

증거 수집이 끝나면 종속성의 역순으로 다음과 같이 정리한다.

1. EC2 종료 후 `terminated`까지 대기
2. 루트 EBS가 `DeleteOnTermination=true`로 삭제됐는지 확인
3. EIP가 생성되지 않았으며 남아 있지 않은지 확인
4. Key Pair와 Security Group 삭제
5. Route Table 연결 해제 및 사용자 정의 Route Table 삭제
6. Public Subnet 삭제
7. IGW를 VPC에서 분리하고 삭제
8. 마지막으로 VPC 삭제

실행 전에는 `./scripts/cleanup-server.sh`로 대상만 조회하고, 실제 정리는
`./scripts/cleanup-server.sh execute`로 수행한다(`--execute`도 동일). 실행 모드는 프로젝트 태그와 정확한
ID를 다시 검증하고 `codyssey-06-1` 확인 문구를 입력해야 삭제를 시작한다.

삭제 전에는 `08-cleanup-before.log`에 대상 ID를 기록하고, 삭제 후에는 프로젝트 태그로
EC2·EBS·EIP·IGW·VPC 등을 다시 조회해 빈 결과를 `09-cleanup-after.log`에 남긴다.

## 완료 판정 근거

- [리소스 정리 체크리스트](../cleanup-checklist.md)
- `../evidence/logs/08-cleanup-before.log` — 정리 실행 후 생성 예정
- `../evidence/logs/09-cleanup-after.log` — 정리 실행 후 생성 예정

`09-cleanup-after.log`가 생성되고 체크리스트의 최소 5종이 체크된 뒤에만 이 답변을
**PASS**로 변경한다.
