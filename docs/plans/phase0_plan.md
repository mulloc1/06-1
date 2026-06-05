# Phase 0 — IAM Setup & Repo Scaffold

> Parent plan: [`docs/plan.md`](../plan.md) §6 Phase 0
> Subject reference: [`docs/subject.md`](../subject.md) §2, §4.4

This phase creates the **lab IAM principal** that every subsequent phase will use, and lays down the **bare-minimum repository skeleton** under `06-1/` so later phases have a stable place to drop docs and evidence. No AWS infrastructure is provisioned yet — that starts in Phase 1. Following `.cursorrules` §4 (Minimal-First / YAGNI), nothing is created here beyond what later phases will immediately consume.

---

## 1. Goal

- Stand up the lab IAM user `lab-cloud-web` with a **single custom managed policy** scoped to EC2/VPC/SG only, plus a narrow self-service inline policy (`plan.md` §4.5).
- Enable **MFA** on the lab user and configure an AWS CLI profile (`[lab]`) so all later phases run as the least-privileged principal — **not** root.
- Create the `06-1/` directory tree exactly as locked in `plan.md` §3 (README skeleton, `docs/`, empty `docs/evidence/`).
- Result: running `aws sts get-caller-identity --profile lab` returns the lab user's ARN, and the repository contains the empty deliverable shells that Phases 1–6 will fill in.

---

## 2. Scope (In / Out)

**In scope**
- AWS root account hygiene: confirm root MFA is on, then **log out of root** for the rest of the lab.
- Create custom managed policy `lab-cloud-web-policy` (JSON from `plan.md` §4.5) in account.
- Create IAM user `lab-cloud-web` with console + programmatic access, attach the custom policy, attach the self-service inline policy, enable virtual MFA.
- Generate one access key pair; configure `~/.aws/credentials [lab]` and `~/.aws/config [profile lab]` (region `ap-northeast-2`).
- Export the policy JSON to `docs/evidence/06-iam-policy.json`.
- Create the `06-1/` directory tree: `README.md` skeleton + `docs/` with `plan.md`, `bonus_plan.md`, `subject.md` already present plus empty `docs/evidence/` folder.

**Out of scope**
- VPC / Subnet / IGW / Route Table provisioning (Phase 1).
- EC2 / SSH key pair / Nginx (Phase 2).
- Any screenshot evidence beyond the IAM policy JSON.
- Bonus IAM permissions (e.g. ACM, ECR) — added in Phase 7 only if needed.

---

## 3. Tasks

### 3.1 Root account safety
- Sign in as root **only** for this phase, only to create the lab user.
- Verify root MFA is enabled (IAM → Security credentials → MFA). If not, enable a virtual MFA device before continuing.
- Confirm there is **no** active root access key (delete if present).

### 3.2 Custom managed policy `lab-cloud-web-policy`
- IAM → Policies → Create policy → JSON tab.
- Paste the policy from `plan.md` §4.5 verbatim (EC2 describe + scoped run/terminate + VPC/SG/IGW/RT/KeyPair/Tags actions on `Resource: "*"`).
- Name: `lab-cloud-web-policy`; description: `Least-privilege policy for 06-1 cloud lab (EC2/VPC/SG only).`
- Save the policy ARN for the next step.

### 3.3 IAM user `lab-cloud-web`
- IAM → Users → Create user.
  - Username: `lab-cloud-web`.
  - Enable **AWS Management Console access**: custom password, do **not** require reset on first sign-in (this is a single-user lab).
  - Enable **programmatic access**: generate one access key, **download the CSV immediately**, store outside the repo.
- Attach the `lab-cloud-web-policy` managed policy directly to the user (no group needed for a one-user lab).
- Add the self-service inline policy from `plan.md` §4.5 (allows `iam:GetUser`, `iam:ListAccessKeys`, `iam:CreateAccessKey`, `iam:DeleteAccessKey`, `iam:UpdateAccessKey` on **only** `arn:aws:iam::<account-id>:user/lab-cloud-web`).
- IAM → Users → `lab-cloud-web` → Security credentials → Assign virtual MFA device; complete the two consecutive code prompts.

### 3.4 Local AWS CLI profile
- Append to `~/.aws/credentials`:
  ```ini
  [lab]
  aws_access_key_id     = <from CSV>
  aws_secret_access_key = <from CSV>
  ```
- Append to `~/.aws/config`:
  ```ini
  [profile lab]
  region = ap-northeast-2
  output = json
  ```
- Verify: `aws sts get-caller-identity --profile lab` returns `arn:aws:iam::<account>:user/lab-cloud-web`.
- Verify denial: `aws s3 ls --profile lab` returns `AccessDenied` (proves no `s3:*`).
- Verify allowance: `aws ec2 describe-vpcs --profile lab` returns the default VPC list without error.

### 3.5 Repo scaffold under `06-1/`
- Confirm the following files already exist (created prior to this phase): `docs/subject.md`, `docs/plan.md`, `docs/bonus_plan.md`. Do not overwrite them.
- Create `06-1/README.md` with a **skeleton only** — title, one-paragraph intro, and section headers that later phases fill in:

  ```markdown
  # 06-1 · Cloud Infrastructure & Web Service Deployment

  Public-facing web service on AWS (VPC + Public Subnet + IGW + EC2 + Nginx) with least-privilege Security Group and IAM, per `docs/subject.md`.

  ## Architecture
  _(diagram added in Phase 4 — see `docs/architecture.png`)_

  ## Public URL & Verification
  _(filled in Phase 3 — chosen method, public IP, evidence screenshots)_

  ## Deliverables
  - Architecture diagram: `docs/architecture.png`
  - Troubleshooting report: `docs/troubleshooting.md`
  - Cleanup checklist: `docs/cleanup-checklist.md`

  ## Cleanup Status
  _(filled in Phase 6)_
  ```

- Create the empty directory `06-1/docs/evidence/` (add `.gitkeep` if the VCS strips empty directories).
- Export the custom managed policy JSON to `06-1/docs/evidence/06-iam-policy.json` (IAM → Policies → `lab-cloud-web-policy` → JSON → copy → save).

---

## 4. Files Touched

| File / Resource | Action |
| ---- | ------ |
| AWS IAM policy `lab-cloud-web-policy` | create (custom managed) |
| AWS IAM user `lab-cloud-web` | create + attach policy + enable MFA + access key |
| `~/.aws/credentials [lab]` | append on learner machine (not committed) |
| `~/.aws/config [profile lab]` | append on learner machine (not committed) |
| `06-1/README.md` | create (skeleton only) |
| `06-1/docs/evidence/` | create (empty + `.gitkeep`) |
| `06-1/docs/evidence/06-iam-policy.json` | create (exported policy JSON) |

> `docs/plan.md`, `docs/bonus_plan.md`, `docs/subject.md` exist before this phase and are **not** touched.

---

## 5. Acceptance Criteria

- [ ] `aws sts get-caller-identity --profile lab` returns the `lab-cloud-web` ARN.
- [ ] `aws s3 ls --profile lab` returns `AccessDenied` (proves no S3 permissions leaked in).
- [ ] `aws iam list-users --profile lab` returns `AccessDenied` (proves the self-service inline policy is scoped to one user only).
- [ ] `aws ec2 describe-vpcs --profile lab --region ap-northeast-2` returns successfully.
- [ ] IAM → Users → `lab-cloud-web` shows **MFA enabled** and **one** active access key.
- [ ] The user has **exactly two** policies attached: `lab-cloud-web-policy` (customer managed) and the self-service inline policy. **No** `AdministratorAccess` is attached anywhere.
- [ ] `06-1/README.md`, `06-1/docs/evidence/`, and `06-1/docs/evidence/06-iam-policy.json` exist; `docs/plan.md`, `docs/bonus_plan.md`, `docs/subject.md` are unchanged.
- [ ] No `.pem`, `.csv`, or `~/.aws/credentials` content is staged in the repo (`git status` shows clean outside the listed files).

---

## 6. Commit

```
docs: scaffold cloud lab readme and implementation plan
```

One commit covers (a) the README skeleton, (b) the empty evidence folder, and (c) the exported IAM policy JSON. Per `.cursorrules` §6 (Logical Commit Unit), AWS console clicks are **not** code changes and live only in the policy JSON evidence file; everything else in this phase is captured in the commit body so a reviewer can replay the IAM setup.

---

## 7. Risks / Notes

- **Never commit the CSV** with the access key or any file matching `*.pem` / `~/.aws/credentials`. Add `*.pem`, `*.csv`, `.aws/` to a project-level `.gitignore` if not already covered globally.
- If `aws ec2 describe-vpcs` fails with `UnauthorizedOperation`, re-check that `lab-cloud-web-policy` includes `ec2:Describe*`; the most common cause is dropping the wildcard in step 3.2.
- If the lab user later needs an additional action (e.g. `ec2:CreateInternetGateway` was missed), **iterate the existing policy** from CloudTrail's `AccessDenied` entries — do **not** attach `AdministratorAccess` "just to unblock". Subject §4.4 explicitly forbids it.
- The CSV is the only copy of the secret access key; rotate via the self-service inline policy if lost. Plan §6 Phase 6 (Cleanup) will revoke the key at lab end.
- Root is **not** used after this phase. If any later step says "log in as root", treat it as a bug in this plan.

---

## 8. Definition of Done

- The lab IAM user exists with the locked policy set, MFA, and a working `[lab]` CLI profile.
- The `06-1/` repo skeleton matches `plan.md` §3 layout for everything that should exist *before* Phase 1 starts.
- Every later phase can run AWS console / CLI actions as `lab-cloud-web` without ever signing in as root.
