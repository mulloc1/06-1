# 질문 15 — IAM 권한 부족 시 최소 권한 찾기

## 질문

IAM 권한 부족으로 작업이 실패하면 권한을 무작정 올리지 않고 어떻게 필요한 최소 범위를 찾는가?

## 답변

먼저 AccessDenied 메시지에서 **서비스, Action, Resource, 조건**을 분리해 확인한다. 예를 들어
`ec2:DescribeInstanceStatus`가 거부됐다고 해서 곧바로 `ec2:*`나 AdministratorAccess를
붙이지 않는다.

점검 순서는 다음과 같다.

1. 요청한 리전과 정책의 `aws:RequestedRegion` 조건이 일치하는지 확인한다.
2. MFA 로그인 또는 STS 임시 세션으로 `aws:MultiFactorAuthPresent=true`인지 확인한다.
3. 올바른 정책이 사용자에 연결됐고 최신 버전이 Default인지 확인한다.
4. 거부된 Action이 기존 와일드카드에 포함되는지 확인한다. 예를 들어
   `ec2:DescribeInstanceStatus`는 `ec2:Describe*`에 포함된다.
5. 실제 누락이라면 AWS Service Authorization Reference에서 해당 동작과 종속 동작을 찾는다.
6. 필요한 Action만 정책에 추가하고 같은 요청을 다시 실행한다.
7. CloudTrail 또는 제한된 오류 로그로 성공 여부를 확인한다.

EC2 콘솔의 CloudWatch 경보와 AWS Health 카드가 거부되더라도 과제 기능에 필요하지 않으면
관련 권한을 추가하지 않는다. 이렇게 “화면의 모든 경고 제거”가 아니라 “과제 기능 수행에
필요한 API만 허용”하는 것을 최소 권한 기준으로 삼는다.

## 실습 근거

- [과제용 IAM 정책](../iam/lab-cloud-web-policy.template.json)
- 정책은 EC2/VPC/SG 작업, MFA와 서울 리전만 허용하며 S3·RDS·IAM 관리 권한은 없다.

