# Cloud Infrastructure & Web Service Deployment Plan (plan.md)

This document is a phased implementation plan that satisfies the requirements in `docs/subject.md` and the coding/structure rules in the repository `.cursorrules`. Following the **Minimal-First / YAGNI** principle (.cursorrules §4) and **Lightweight Plans** (.cursorrules §2), we provision the **minimum AWS footprint that meets requirements**; bonus tasks (subject §5) are separated into a later phase after the core mission is done and torn down or stabilized.

---

## 1. Goal Summary

- Build a **publicly reachable web service** on AWS using **VPC + public subnet + Internet Gateway + EC2 + Security Group + IAM** as one coherent stack (subject §1, §2, §4.1–§4.4).
- Provide **four deliverables**: an architecture diagram, an external-access proof (browser screenshot or `GET /health` 200), a troubleshooting report (≥ 1 case), and a resource cleanup checklist (subject §2.1–§2.4).
- Apply **least privilege end-to-end**: Security Group inbound only on **HTTP 80 (0.0.0.0/0)** and **SSH 22 (learner IP only)**; lab IAM principal scoped to **EC2/VPC/SG** only, **no `AdministratorAccess`** (subject §4.3, §4.4).
- Show **outbound** connectivity from the EC2 instance (`curl https://example.com`) and **inbound** connectivity from the public internet (`http://<public-ip>` or `GET /health`) (subject §4.1, §4.5).
- Document **one full troubleshooting cycle** — symptom → hypothesis → verification → action → result → prevention — using real evidence (CloudWatch / `journalctl` / `curl -v`) (subject §2.3, §3·4).
- Avoid surprise billing by completing the **cleanup checklist** with screenshots showing every chargeable resource terminated/deleted (subject §2.4, §4.6).

---

## 2. Locked Decisions

Decisions for items left open in subject (provider, region, AMI, instance size, web server, etc.) and other choices that are costly to reverse later. Per-rule descriptions, SG rule names, and policy ARNs are finalized during implementation (.cursorrules §2).

| Item | Decision | Rationale (subject / .cursorrules) |
| ---- | -------- | ---------------------------------- |
| Cloud provider | **AWS** | Subject vocabulary (VPC / EC2 / Security Group / IAM) is AWS-native; free-tier covers the lab |
| Region | **`ap-northeast-2` (Seoul)** | Lowest latency for the learner; consistent for screenshots |
| Provisioning method | **AWS Console** (click-through) + recorded screenshots | Subject grading is evidence-based; IaC is YAGNI for a one-shot lab (.cursorrules §4) |
| VPC CIDR | **`10.0.0.0/16`** | Standard private range; leaves room if future subnets are added in bonus |
| Public subnet CIDR | **`10.0.1.0/24`** in one AZ (`ap-northeast-2a`) | Single AZ is enough for subject §4.1 (1 public subnet); one AZ keeps cleanup simple |
| Internet Gateway | **1 IGW** attached to the VPC; route table `0.0.0.0/0 → IGW` on the public subnet | Subject §4.1 |
| EC2 AMI | **Amazon Linux 2023** (latest x86_64) | Free-tier eligible, recent kernel, `dnf` ships Nginx |
| EC2 instance type | **`t3.micro`** | Free-tier eligible in `ap-northeast-2`; sufficient for Nginx |
| EBS | Default 8 GiB **gp3** root volume; **delete on termination = true** | Cleanup-friendly; gp3 cheaper than gp2 (.cursorrules §4 minimal) |
| Public IP | **Auto-assign public IPv4** on launch; **no Elastic IP** in core scope | Avoids EIP idle charge; EIP is reserved for the HTTPS bonus when a stable IP matters |
| Key pair | **One ED25519 SSH key** created for this lab; private key stored locally outside the repo | Subject §4.2 SSH; never commit `.pem`/private keys |
| Web server | **Nginx** from the distro repo (`dnf install nginx`); default `/usr/share/nginx/html` content + a custom `/health` location returning fixed text | Subject §4.2; satisfies both verification methods (A) and (B) |
| External-access verification | **Method (B): `GET /health` → 200 `OK`** (browser screenshot of method A is included as supporting evidence) | (B) is deterministic and trivially scriptable; (A) gives a human-readable screenshot |
| Security Group — name | `lab-web-sg` (one SG, attached to the EC2 ENI) | Single SG simplifies grading |
| Security Group — inbound | `tcp/80` from `0.0.0.0/0`; `tcp/22` from `<learner-IP>/32` only | Subject §4.3 (no 0–65535 from 0.0.0.0/0) |
| Security Group — outbound | Default `all/all` to `0.0.0.0/0` | Required for `dnf` install and `curl https://example.com` proof |
| IAM principal | **One lab IAM user** named `lab-cloud-web` with programmatic + console access; **no root usage** beyond initial setup | Subject §4.4 |
| IAM policy | **Custom managed policy `lab-cloud-web-policy`** with explicit `ec2:*` (read + scoped run/terminate) and `iam:GetUser`/`iam:ListAccessKeys` for self-service; **no `*:*`**, **no `AdministratorAccess`** | Subject §4.4 forbids admin; managed policy is cleaner to attach/detach |
| IAM MFA | MFA **enabled** on the lab user; access keys rotated/revoked at cleanup | Industry baseline; cheap and explicit |
| Logs / evidence | Nginx `access.log` + `error.log` (default paths), `journalctl -u nginx`, `curl -v` output captured to `docs/evidence/` | Used in the troubleshooting report |
| Documentation language | **English**, Markdown only | Consistent with subject and prior assignments |
| Diagram tooling | **draw.io / diagrams.net** exported to **PNG**, saved as `docs/architecture.png` | Subject §2.1 PNG/PDF; PNG renders inline in GitHub README |
| Repo scope | This assignment lives under `06-1/`; only `06-1/README.md`, `06-1/docs/*` are produced — no application source code is committed for the core mission | Subject deliverables are docs + evidence, not code |

---

## 3. Directory / File Layout

Follows subject §2 (one file per deliverable under `docs/`). No application code directory is created in core scope; the EC2 instance serves the default Nginx page plus a `/health` snippet configured **in place on the instance**, not in the repo (.cursorrules §4 — split after evidence).

```
06-1/
├── README.md                       # intro · architecture summary · public URL · screenshots · verification method · cleanup status
├── docs/
│   ├── subject.md
│   ├── plan.md                     # (this document)
│   ├── bonus_plan.md               # HTTPS + Docker bonus (separate phase)
│   ├── architecture.png            # one-page diagram (subject §2.1)
│   ├── troubleshooting.md          # ≥ 1 troubleshooting case (subject §2.3)
│   ├── cleanup-checklist.md        # resource cleanup checklist (subject §2.4)
│   └── evidence/
│       ├── 01-curl-health.png      # GET /health → 200 OK
│       ├── 02-browser-root.png     # http://<public-ip> rendered page
│       ├── 03-ssh-localhost.png    # curl http://localhost on the instance
│       ├── 04-outbound-curl.png    # curl https://example.com from instance
│       ├── 05-sg-inbound.png       # Security Group rules screenshot
│       ├── 06-iam-policy.json      # exported custom managed policy JSON
│       └── 07-cleanup-*.png        # post-teardown screenshots (per resource)
```

**Layout rationale (.cursorrules §4·§5 SRP)**

- Each deliverable in subject §2 has exactly one file; no nested folders by topic — flat docs read faster for graders.
- `docs/evidence/` is a single place for screenshots referenced by both `troubleshooting.md` and `README.md`; numbering keeps them stable across edits.
- `06-1/README.md` is the entry point and links into the four deliverables; the diagram is referenced as a relative path.

---

## 4. Architecture Overview

### 4.1 Network Topology (subject §4.1)

```
Internet
   │
   ▼
[ Internet Gateway ]   ── attached to VPC (10.0.0.0/16)
   │
   ▼
[ Route Table ]        ── public-rt: 0.0.0.0/0 → IGW; 10.0.0.0/16 → local
   │
   ▼
[ Public Subnet 10.0.1.0/24, AZ ap-northeast-2a ]
   │
   ▼
[ EC2 t3.micro · Amazon Linux 2023 · Nginx ]
   │  public IPv4 (auto-assigned), private 10.0.1.x
   │  ENI attached to security group `lab-web-sg`
   ▼
[ Security Group: lab-web-sg ]
     inbound:  80/tcp  ← 0.0.0.0/0
               22/tcp  ← <learner-IP>/32
     outbound: all/all → 0.0.0.0/0
```

- **One** VPC, **one** public subnet, **one** IGW, **one** route table associated with the subnet — the minimum from subject §4.1.
- A second AZ / private subnet / NAT Gateway is **explicitly out of scope** for core; NAT GW would incur hourly charges with no learning value here (.cursorrules §4 YAGNI).

### 4.2 Traffic Flow (subject §3·1, §4.5)

| Direction | Path | Verification |
| --------- | ---- | ------------ |
| External → service (inbound) | client → IGW → route table → ENI public IP → `lab-web-sg` (80) → Nginx | `curl -i http://<public-ip>/health` returns `HTTP/1.1 200 OK` with body `OK` |
| Instance → internet (outbound) | EC2 → SG egress → route table (`0.0.0.0/0` via IGW) → internet | `curl -sI https://example.com` returns `HTTP/2 200` |
| Operator → instance (SSH) | learner IP → IGW → ENI → `lab-web-sg` (22) → sshd | `ssh -i lab.pem ec2-user@<public-ip>` succeeds; from any other IP it times out |

### 4.3 Web Server Surface (subject §4.2, §4.5)

- Nginx default config + one extra `location` block on port 80:

```nginx
server {
    listen 80 default_server;
    server_name _;

    location / {
        root /usr/share/nginx/html;
        index index.html;
    }

    location = /health {
        access_log off;
        default_type text/plain;
        return 200 "OK\n";
    }
}
```

- `index.html` is left as the distro default plus a single learner-edited line so the browser screenshot (method A) is clearly _this_ instance.
- Service managed via `systemctl enable --now nginx`; restart on edit with `sudo systemctl reload nginx`.

### 4.4 Access Control (Security Group · subject §4.3)

| Rule | Protocol/Port | Source | Reason |
| ---- | ------------- | ------ | ------ |
| Inbound | tcp/80 | 0.0.0.0/0 | Public HTTP (subject §4.3) |
| Inbound | tcp/22 | `<learner-IP>/32` | SSH for the learner only |
| Inbound | _none else_ | — | Subject §4.3 forbids all-ports-from-anywhere |
| Outbound | all/all | 0.0.0.0/0 | `dnf install`, `curl https://example.com`, package upgrades |

- The learner IP is captured with `curl -4 https://checkip.amazonaws.com` and pinned to a `/32`; if it changes the SG rule is updated, not widened to `0.0.0.0/0`.
- ICMP is **not** opened in core scope; ping is not a verification method here.

### 4.5 IAM Least Privilege (subject §4.4)

Two-tier separation:

1. **Root account**: used only to create the lab IAM user and attach the custom policy, then logged out. MFA on root mandatory.
2. **Lab IAM user `lab-cloud-web`**: receives a **single custom managed policy** `lab-cloud-web-policy` plus an inline read-only self-service policy for its own keys.

`lab-cloud-web-policy` (sketch — finalized during implementation; .cursorrules §2):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "VpcAndSgDescribeAndManage",
      "Effect": "Allow",
      "Action": [
        "ec2:Describe*",
        "ec2:CreateVpc",       "ec2:DeleteVpc",
        "ec2:CreateSubnet",    "ec2:DeleteSubnet",
        "ec2:CreateInternetGateway", "ec2:AttachInternetGateway", "ec2:DetachInternetGateway", "ec2:DeleteInternetGateway",
        "ec2:CreateRouteTable","ec2:DeleteRouteTable","ec2:AssociateRouteTable","ec2:DisassociateRouteTable","ec2:CreateRoute","ec2:DeleteRoute",
        "ec2:CreateSecurityGroup","ec2:DeleteSecurityGroup","ec2:AuthorizeSecurityGroup*","ec2:RevokeSecurityGroup*",
        "ec2:RunInstances","ec2:TerminateInstances","ec2:StartInstances","ec2:StopInstances",
        "ec2:CreateKeyPair","ec2:DeleteKeyPair","ec2:ImportKeyPair",
        "ec2:CreateTags","ec2:DeleteTags"
      ],
      "Resource": "*"
    }
  ]
}
```

Explicit non-permissions:

- **No** `iam:*` on other principals.
- **No** `s3:*`, `rds:*`, `lambda:*`, `route53:*` — unrelated to this lab (subject §4.4).
- **No** `AdministratorAccess`, `PowerUserAccess`, or `*:*`.

Self-service inline policy on the same user (so they can rotate their own keys without root):

```json
{
  "Effect": "Allow",
  "Action": ["iam:GetUser","iam:ListAccessKeys","iam:CreateAccessKey","iam:DeleteAccessKey","iam:UpdateAccessKey"],
  "Resource": "arn:aws:iam::<account-id>:user/lab-cloud-web"
}
```

---

## 5. Output / Verification Specification (Acceptance UI States)

Use the visual/behavior spec below as the baseline for README screenshots and the troubleshooting report (no automated test suite required).

### 5.1 External Access (subject §2.2, §4.5)

| Check | Command / Action | Expected |
| ----- | ---------------- | -------- |
| Method (B) primary | `curl -i http://<public-ip>/health` | `HTTP/1.1 200 OK` + body `OK` |
| Method (A) secondary | Browser `http://<public-ip>` | Default Nginx page with one custom line; HTTP, not HTTPS |
| Local on instance | `curl -i http://localhost` | `200 OK` (subject §4.2) |
| Outbound | `curl -sI https://example.com` | `HTTP/2 200` |

### 5.2 Security Group — Negative Tests

- From an **unauthorized IP**: `ssh -i lab.pem ec2-user@<public-ip>` times out (port 22 closed).
- Attempt `nc -zv <public-ip> 3306` from anywhere: connection refused/filtered (no DB port open).
- Attempt `nc -zv <public-ip> 8080` from anywhere: connection refused/filtered.

### 5.3 IAM — Negative Tests

- Signed in as `lab-cloud-web`, attempt `aws s3 ls`: `AccessDenied`.
- Attempt `aws iam list-users`: `AccessDenied`.
- Attempt `aws ec2 describe-instances`: succeeds.

Screenshots of denied calls are captured into `docs/evidence/` and referenced in `troubleshooting.md` if relevant.

---

## 6. Phased Implementation Plan

Each phase = **one logical change = one commit** (.cursorrules §6 Logical Commit Unit), with Conventional Commits prefixes. (.cursorrules §2 "coarse steps: 3–7")

### Phase 0 — IAM Setup & Repo Scaffold

- Create `lab-cloud-web` IAM user, attach `lab-cloud-web-policy`, enable MFA, generate access keys, configure `~/.aws/credentials [lab]` profile locally.
- Add `06-1/README.md` skeleton and this `docs/plan.md`.
- Commit: `docs: scaffold cloud lab readme and implementation plan`

### Phase 1 — Network (VPC + Subnet + IGW + Route Table)

- As the `lab` profile, create VPC `10.0.0.0/16`, public subnet `10.0.1.0/24` in `ap-northeast-2a`, IGW attached to VPC, public route table with `0.0.0.0/0 → IGW`, associate it with the subnet.
- Enable `MapPublicIpOnLaunch = true` on the subnet.
- Commit: `docs: record vpc, subnet, igw, and route table provisioning`

### Phase 2 — EC2 + Nginx + Local Check

- Launch `t3.micro` (Amazon Linux 2023) in the public subnet with the key pair; `lab-web-sg` attached (rules from §4.4).
- `sudo dnf install -y nginx`, drop the `/health` location, `systemctl enable --now nginx`.
- Verify on-instance: `curl -i http://localhost` → 200; `curl -sI https://example.com` → 200.
- Capture `docs/evidence/03-ssh-localhost.png`, `04-outbound-curl.png`.
- Commit: `docs: launch ec2, install nginx, and verify local and outbound`

### Phase 3 — External Access Proof

- From the learner's machine: `curl -i http://<public-ip>/health` → 200 (capture `01-curl-health.png`); open browser → `02-browser-root.png`.
- Update `06-1/README.md` with the chosen verification method (B), the URL/IP, and the two screenshots.
- Commit: `docs: verify external http access with /health and browser`

### Phase 4 — Architecture Diagram

- Author the one-page diagram in draw.io with the components from §4.1 (Internet → IGW → Route Table → Public Subnet → EC2 → SG); export PNG to `docs/architecture.png`.
- Embed in `06-1/README.md`.
- Commit: `docs: add one-page architecture diagram`

### Phase 5 — Troubleshooting Report

- Pick one real issue encountered during Phases 1–3 (or fabricate a reproducible one such as missing SG rule, missing route, wrong AMI userdata) and document it as `docs/troubleshooting.md` using the **symptom → hypothesis → verification → action → result → prevention** template.
- Reference at least one piece of evidence in `docs/evidence/` (log excerpt, `curl -v`, SG screenshot).
- Commit: `docs: add troubleshooting report with one full cycle`

### Phase 6 — Cleanup Checklist & Teardown

- Write `docs/cleanup-checklist.md` covering EC2 instance, EBS volume, Elastic IP (none in core, but documented as N/A), Internet Gateway, VPC, security group, key pair, IAM user (or de-permission).
- Execute the teardown in order; capture post-teardown screenshots `07-cleanup-*.png` (Billing console or per-resource list).
- Update `README.md` "Cleanup Status" with the final state.
- Commit: `docs: add cleanup checklist and teardown evidence`

### Phase 7 (Optional) — Bonus (subject §5)

- Only after the four core deliverables are submitted, in separate commits, on a branch (.cursorrules §4 YAGNI).
- See `docs/bonus_plan.md` for HTTPS and Docker phases.

---

## 7. Verification Strategy

This assignment has no automated test suite; use a **manual verification checklist** for acceptance. Per `.cursorrules` §6 (Testing Determinism), network-dependent verification is done manually with captured evidence, not asserted in code.

Checklist:

- [ ] **Network**: VPC `10.0.0.0/16`, subnet `10.0.1.0/24`, IGW attached, public route table has `0.0.0.0/0 → IGW` and is associated with the subnet.
- [ ] **Outbound**: on the instance `curl -sI https://example.com` returns `200`.
- [ ] **EC2**: instance is `t3.micro` in the public subnet with auto-assigned public IPv4; `systemctl is-active nginx` returns `active`.
- [ ] **Local HTTP**: on the instance `curl -i http://localhost` returns `200`.
- [ ] **External HTTP**: from the learner's machine `curl -i http://<public-ip>/health` returns `200 OK` with body `OK`; browser `http://<public-ip>` renders the page.
- [ ] **SG inbound**: only `80/tcp` from `0.0.0.0/0` and `22/tcp` from `<learner-IP>/32`; no `0–65535` rule; screenshot in `evidence/`.
- [ ] **SG SSH negative**: SSH from any non-learner IP times out.
- [ ] **IAM**: lab user has **no** `AdministratorAccess`; `aws s3 ls` denied; `aws ec2 describe-instances` allowed; policy JSON exported to `evidence/06-iam-policy.json`.
- [ ] **Diagram**: `docs/architecture.png` exists, shows VPC / Subnet / IGW / EC2 / SG / external→service flow on one page.
- [ ] **Troubleshooting**: `docs/troubleshooting.md` has ≥ 1 case with all six fields filled.
- [ ] **Cleanup**: `docs/cleanup-checklist.md` lists EC2, EBS, EIP (N/A), IGW, VPC, SG, key pair, IAM user, each ticked with a screenshot.
- [ ] **README**: states chosen verification method (A or B), public URL/IP, embedded diagram, and links to the three other docs.

---

## 8. Risks / Deferred Decisions

| Item | Risk | Mitigation |
| ---- | ---- | ---------- |
| Public IPv4 changes on stop/start | Public IP rotates if the instance is stopped, breaking screenshots/URLs in README | Do not stop the instance during the lab; if stopped, retake screenshots; defer Elastic IP to the HTTPS bonus |
| Learner IP changes (mobile / ISP) | SSH rule `<learner-IP>/32` stops matching, locking out the operator | Update the SG rule from the AWS console (web access still works); document in `troubleshooting.md` if encountered |
| Free-tier overrun | `t3.micro` hours, EBS GiB-month, public IPv4 hourly charge (post-Feb 2024) accumulate | Tear down within hours of completing screenshots; capture Billing screenshot at cleanup |
| `userdata` quirks (Nginx not installed) | Boot-time install fails silently → external check fails | Install Nginx interactively via SSH in Phase 2 instead of `userdata`; visible logs |
| SG rule widened during debugging | Tempting to open `0.0.0.0/0:0–65535` to "see if it's the SG" | Forbidden by subject §4.3; use `curl -v` and `nc -vz` from the instance + outside to triangulate |
| IAM policy too narrow | Console actions fail mid-lab; learner reaches for `AdministratorAccess` | Iterate the custom policy from CloudTrail "AccessDenied" entries; never attach AdministratorAccess |
| Diagram tooling drift | Screenshot from a future edit looks different than the README description | Keep `architecture.png` as the single source; rebuild from `architecture.drawio` (kept locally) if the diagram changes |
| Region drift | Resources accidentally created in `us-east-1` are missed during cleanup | Always check the region dropdown before each console action; cleanup checklist enumerates the region per item |

---

## 9. Definition of Done

- All four deliverables in subject §2 exist and are committed: `docs/architecture.png`, README with external-access proof + ≥ 1 screenshot, `docs/troubleshooting.md`, `docs/cleanup-checklist.md`.
- Functional requirements §4.1–§4.6 all pass the §7 checklist: VPC + subnet + IGW + route, EC2 + SSH + Nginx + local 200, SG least-privilege, IAM least-privilege, external access (method B with method A as backup), cleanup executed.
- No SG rule allows `0–65535` from `0.0.0.0/0`; no IAM principal in this lab carries `AdministratorAccess`.
- All five learning objectives in subject §3 can be explained from this plan §4 and the captured evidence:
  1. Roles of **VPC / Subnet / Route Table / IGW** and traffic flow (§4.1, §4.2).
  2. Difference between **Security Group** and **IAM**, and how least privilege is applied (§4.4, §4.5).
  3. Settings needed for external requests to reach the EC2 web server (§4.1, §4.2, §4.4).
  4. **Hypothesis → verification → action** loop in `docs/troubleshooting.md` (Phase 5).
  5. Common **billing** drivers and safe **cleanup order** in `docs/cleanup-checklist.md` (Phase 6).
- The bonus phase (HTTPS + Docker, `docs/bonus_plan.md`) is started **only after** this DoD is met.
