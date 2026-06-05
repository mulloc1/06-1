# Phase 6 — Cleanup Checklist & Teardown

> Parent plan: [`docs/plan.md`](../plan.md) §6 Phase 6
> Subject reference: [`docs/subject.md`](../subject.md) §2.4, §4.6

This phase produces the **resource cleanup deliverable** required by subject §2.4 and prevents surprise billing per subject §4.6. It authors `docs/cleanup-checklist.md` with an ordered teardown list (EC2 → EBS → IGW → VPC → SG → key pair → IAM user), executes the teardown, captures post-teardown evidence, and updates `README.md` "Cleanup Status" with the final state.

---

## 1. Goal

- Author `06-1/docs/cleanup-checklist.md` enumerating every chargeable + non-chargeable AWS resource created in Phases 0–2, ordered safely (dependents before dependencies).
- Execute the teardown end-to-end, ticking each item as deleted.
- Capture per-resource post-teardown screenshots into `docs/evidence/07-cleanup-*.png`.
- Update `06-1/README.md` "Cleanup Status" with the final clean state and a Billing console screenshot showing no ongoing charge from this lab.
- Result: zero billable resources from this lab remain in `ap-northeast-2` (or anywhere else), evidenced by screenshots, and the IAM user is deactivated or deleted.

---

## 2. Scope (In / Out)

**In scope**
- AWS resource teardown in `ap-northeast-2`:
  1. EC2 instance `lab-cloud-web-ec2` → terminate (`DeleteOnTermination = true` on the root EBS volume removes the 8 GiB gp3 with it).
  2. Security Group `lab-web-sg` → delete.
  3. Key Pair `lab-cloud-web-key` (AWS-side public half) → delete.
  4. Route Table `lab-cloud-web-public-rt` → disassociate subnet, delete.
  5. Internet Gateway `lab-cloud-web-igw` → detach from VPC, delete.
  6. Subnet `lab-cloud-web-public-subnet` → delete.
  7. VPC `lab-cloud-web-vpc` → delete.
  8. IAM user `lab-cloud-web` → deactivate access key, then delete user (or detach all policies + remove MFA + delete keys, depending on preference for "re-usable lab user" vs "fully torn down").
  9. Custom managed policy `lab-cloud-web-policy` → delete (after detach from the user).
- Verification: AWS Billing console → "Bills" tab, current month → screenshot showing the lab's resources no longer accrue.
- README "Cleanup Status" section: bullet list of each resource with state `Deleted` and a link to the corresponding `07-cleanup-*.png`.

**Out of scope**
- Anything in a region other than `ap-northeast-2` — there shouldn't be anything else, but if the cleanup checklist verification surfaces a stray, document it in `troubleshooting.md` as a second case (not in this phase).
- Deleting the AWS root account or removing root MFA. Root remains intact.
- Removing local files (`~/.ssh/lab-cloud-web-key.pem`, `~/.aws/credentials [lab]`) — they're harmless once the AWS side is gone, but for hygiene the checklist mentions them.
- Bonus cleanup (HTTPS / Docker). Those have their own teardown described in `bonus_plan.md`.

---

## 3. Tasks

### 3.1 Author `docs/cleanup-checklist.md`
Use exactly this skeleton; each row is an actionable checkbox the learner ticks as they go:

```markdown
# Cleanup Checklist — 06-1 Cloud Lab

> Required by `docs/subject.md` §2.4. Order matters: dependents are deleted before
> dependencies (instance before SG; SG/subnet/IGW before VPC). Region: `ap-northeast-2`.

| # | Resource | Identifier | Action | Why this order | Evidence |
| --- | --- | --- | --- | --- | --- |
| 1 | EC2 instance | `lab-cloud-web-ec2` | Terminate | Root EBS auto-deletes; releases public IPv4 (post-Feb-2024 hourly charge stops) | `07-cleanup-01-ec2.png` |
| 2 | EBS volume | (root volume of EC2) | Auto-deleted by step 1 | `DeleteOnTermination = true` per `plan.md` §2 | `07-cleanup-02-ebs.png` (Volumes list empty) |
| 3 | Elastic IP | _None in core scope_ | N/A | EIP not allocated; see `bonus_plan.md` if HTTPS phase ran | _N/A_ |
| 4 | Security Group | `lab-web-sg` | Delete | Must be detached (instance gone in step 1) before VPC delete | `07-cleanup-03-sg.png` |
| 5 | Key Pair | `lab-cloud-web-key` (AWS public half) | Delete | Cosmetic — private half stays local; AWS no longer references it | `07-cleanup-04-keypair.png` |
| 6 | Route Table | `lab-cloud-web-public-rt` | Disassociate subnet, Delete | VPC delete fails while custom route tables exist | `07-cleanup-05-rt.png` |
| 7 | Internet Gateway | `lab-cloud-web-igw` | Detach from VPC, Delete | VPC delete fails while IGW is attached | `07-cleanup-06-igw.png` |
| 8 | Subnet | `lab-cloud-web-public-subnet` | Delete | VPC delete fails while subnets exist | `07-cleanup-07-subnet.png` |
| 9 | VPC | `lab-cloud-web-vpc` | Delete | Last network step | `07-cleanup-08-vpc.png` |
| 10 | IAM access key | (for `lab-cloud-web`) | Deactivate, then delete | Stops the key from being used post-lab | `07-cleanup-09-iam-key.png` |
| 11 | IAM user | `lab-cloud-web` | Detach policies, delete MFA, delete user | After resources gone, the user has nothing left to do | `07-cleanup-10-iam-user.png` |
| 12 | IAM policy | `lab-cloud-web-policy` (customer managed) | Delete | Detached in step 11, safe to remove | `07-cleanup-11-iam-policy.png` |
| 13 | Local `~/.ssh/lab-cloud-web-key.pem` | (learner laptop) | Optional `rm` | Hygiene; AWS no longer accepts it after step 5 | _Optional_ |
| 14 | Local `~/.aws/credentials [lab]` | (learner laptop) | Remove the `[lab]` block | The key is already revoked; keeps the credentials file tidy | _Optional_ |
| 15 | Billing console | Bills tab, current month | Screenshot | Proves no lingering charge | `07-cleanup-12-billing.png` |

## Verification CLI

After deletion (from any working CLI profile, since `[lab]` is gone):
```bash
aws ec2 describe-instances     --region ap-northeast-2 --filters Name=tag:Name,Values=lab-cloud-web-ec2     # empty
aws ec2 describe-vpcs          --region ap-northeast-2 --filters Name=tag:Name,Values=lab-cloud-web-vpc     # empty
aws ec2 describe-security-groups --region ap-northeast-2 --filters Name=group-name,Values=lab-web-sg        # empty
aws ec2 describe-internet-gateways --region ap-northeast-2 --filters Name=tag:Name,Values=lab-cloud-web-igw  # empty
aws iam get-user --user-name lab-cloud-web                                                                   # NoSuchEntity
```
```

### 3.2 Execute teardown
Walk rows 1 → 12 in order. For each row:
1. Perform the delete in the AWS console (or CLI).
2. After the resource disappears from the relevant list view, screenshot that **empty list** (or "deleted" status panel) → `docs/evidence/07-cleanup-NN-*.png` matching the table.
3. Tick the row's checkbox in `cleanup-checklist.md`.

Row 1 (EC2 terminate) takes 2–5 minutes; row 2 (EBS auto-delete) is verified by an empty Volumes list filtered to `lab-cloud-web-*`. Row 6 (Route Table) will refuse to delete unless the subnet association is removed first — the table's "Why this order" column already accounts for this.

### 3.3 Billing verification
- Wait at least 24 hours after teardown if possible; AWS billing data lags. If grading is tighter, capture the current-day Cost Explorer view filtered to `ap-northeast-2` instead — the same "no new line items" effect.
- Screenshot the Billing dashboard → `docs/evidence/07-cleanup-12-billing.png`.

### 3.4 README cleanup status
- Edit `06-1/README.md` → "Cleanup Status" section:

  ```markdown
  ## Cleanup Status

  Teardown executed on `<YYYY-MM-DD>`. Per `docs/cleanup-checklist.md`:

  - [x] EC2 instance terminated → `docs/evidence/07-cleanup-01-ec2.png`
  - [x] EBS volume auto-deleted → `docs/evidence/07-cleanup-02-ebs.png`
  - [x] Security Group deleted → `docs/evidence/07-cleanup-03-sg.png`
  - [x] Key pair deleted → `docs/evidence/07-cleanup-04-keypair.png`
  - [x] Route table deleted → `docs/evidence/07-cleanup-05-rt.png`
  - [x] Internet Gateway detached & deleted → `docs/evidence/07-cleanup-06-igw.png`
  - [x] Subnet deleted → `docs/evidence/07-cleanup-07-subnet.png`
  - [x] VPC deleted → `docs/evidence/07-cleanup-08-vpc.png`
  - [x] IAM access key deactivated & deleted → `docs/evidence/07-cleanup-09-iam-key.png`
  - [x] IAM user deleted → `docs/evidence/07-cleanup-10-iam-user.png`
  - [x] IAM policy deleted → `docs/evidence/07-cleanup-11-iam-policy.png`
  - [x] Billing console verified → `docs/evidence/07-cleanup-12-billing.png`

  No EIP was allocated in core scope (see `docs/plan.md` §2 decisions).
  ```

---

## 4. Files Touched

| File | Action |
| ---- | ------ |
| `06-1/docs/cleanup-checklist.md` | create |
| `06-1/docs/evidence/07-cleanup-01-ec2.png` … `07-cleanup-12-billing.png` | create (one per teardown step) |
| `06-1/README.md` | edit ("Cleanup Status" section) |
| AWS resources from Phases 0–2 | delete (per table) |

---

## 5. Acceptance Criteria

- [ ] Every CLI verification command in `cleanup-checklist.md` §"Verification CLI" returns empty / `NoSuchEntity`.
- [ ] `06-1/docs/cleanup-checklist.md` exists, has all 15 rows from §3.1, and every row that is not `N/A` has its checkbox ticked and its evidence file path present + resolving.
- [ ] All `07-cleanup-*.png` files exist under `docs/evidence/`.
- [ ] `06-1/README.md` "Cleanup Status" section enumerates the teardown with a date and per-item evidence links.
- [ ] AWS Billing dashboard or Cost Explorer shows **no** active line items for `lab-cloud-web-*` resources after teardown (screenshot in evidence).
- [ ] IAM user `lab-cloud-web` is deleted (or, if retained for re-runs, has its access key deactivated and its custom policy detached — explicitly stated in the README which path was taken).
- [ ] The repository contains no `*.pem` / `*.csv` files.

---

## 6. Commit

```
docs: add cleanup checklist and teardown evidence
```

One commit per `.cursorrules` §6 (Logical Commit Unit). Bundles `cleanup-checklist.md`, all `07-cleanup-*.png` evidence, and the README "Cleanup Status" update.

---

## 7. Risks / Notes

- **Order matters**. AWS will refuse to delete a VPC that has any of: ENI, subnet, IGW attachment, custom route table, custom SG. The §3.1 table is in the correct order; deviating leads to ugly cascade errors that are recoverable but waste time.
- **Region drift trap** (`plan.md` §8): if any resource was accidentally created in another region during Phases 1–2, this phase will not delete it. Run `aws ec2 describe-instances` and `describe-vpcs` against `us-east-1` and `ap-northeast-1` (the two most likely accidents) as part of step 3.3. If any found, delete them and add a `troubleshooting.md` case for the drift.
- **Public IPv4 charge** (post-Feb-2024): the free-tier no longer covers idle public IPv4 hours. Terminating the EC2 in step 1 stops the meter; do not stop-and-leave the instance overnight before this phase.
- **Don't delete the lab IAM user before deleting AWS resources**. The CLI session loses its only credentials and the rest of the teardown must happen via root, which forces an additional MFA flow and breaks the "no root after Phase 0" rule.
- **The `lab-cloud-web-policy` customer managed policy cannot be deleted while attached**. The §3.1 table places policy deletion after user deletion for this reason.
- If the lab is being re-run for a different cohort, prefer "deactivate access key + detach policy" (rows 10–12 partial) rather than full user deletion — recreating MFA on a virtual device is slow. The README "Cleanup Status" must spell out which option was chosen.

---

## 8. Definition of Done

- All AWS resources from Phases 0–2 are deleted (or for the IAM user, fully neutralized) in `ap-northeast-2`, with screenshot evidence for each step.
- `docs/cleanup-checklist.md` is the canonical record of what was deleted, in what order, with what evidence.
- README "Cleanup Status" reflects the final state with a date.
- Subject §2.4 deliverable is closed. Combined with Phases 3, 4, and 5, **all four subject §2 deliverables** are now complete and the lab is safe to leave.
