# Phase 5 — Troubleshooting Report

> Parent plan: [`docs/plan.md`](../plan.md) §6 Phase 5
> Subject reference: [`docs/subject.md`](../subject.md) §2.3, §3·4

This phase produces the **troubleshooting deliverable** required by subject §2.3: at least one real (or faithfully reproduced) issue from Phases 1–3, documented with the six-field template **symptom → hypothesis → verification → action → result → prevention**, with concrete evidence pulled from CloudWatch / `journalctl` / `curl -v` / AWS console screenshots. Subject §3·4 says the learner must demonstrate the **hypothesis → verification → action** loop; this file is where that loop is written down.

---

## 1. Goal

- Pick **one** issue actually encountered during Phases 1–3. If no real issue arose, deliberately reproduce one of the recurring failure modes called out in `plan.md` §8 (e.g. missing route, missing SG rule, wrong AMI userdata) so the case is genuine and reproducible.
- Write the case into `06-1/docs/troubleshooting.md` using the locked six-field template.
- Reference at least one piece of evidence in `docs/evidence/` (log excerpt, `curl -v` capture, SG/route table screenshot).
- Result: a reviewer can read the report, run the same commands, see the same symptom, and follow the same fix.

---

## 2. Scope (In / Out)

**In scope**
- One full troubleshooting cycle, written in `troubleshooting.md`.
- Inline or referenced evidence (logs, screenshots, command output) from `docs/evidence/`.
- Brief "prevention" guidance that ties back to a section in `plan.md` (so future learners don't repeat the same mistake).
- Optional second case if a second genuine issue happened — subject §2.3 says **≥1**, not exactly 1.

**Out of scope**
- Fabricated issues with no reproducible evidence. The whole grading criterion is "you can prove the loop happened" (subject §3·4); a story without logs/screens does not count.
- Generic "what is a Security Group" theory write-ups. The file is a **case study**, not a tutorial.
- Modifying the architecture in service of the report (changing the SG just to write about it). If a real bug exists, fix it in place and document the fix; if not, choose a documented reproduction case from §3.4 below.

---

## 3. Tasks

### 3.1 Decide the case
Pick the first one of the following that applies. Preference: a real bug you actually hit.

A. **Real case from Phase 1–3** — anything that took more than a minute to root-cause. Examples:
- Nginx `nginx -t` failed because Amazon Linux 2023 ships a default `default_server` block in `/etc/nginx/nginx.conf` colliding with `health.conf`.
- External `curl http://<public-ip>/health` returned `Connection refused` while local `curl http://localhost/health` returned 200.
- SSH succeeded from learner laptop but failed from a phone hotspot (proves the `/32` rule works — borderline a non-issue, but a good positive verification case).

B. **Reproduced reference case** from `plan.md` §8 if no real issue exists. The cleanest choices:
- Missing public route: detach the `0.0.0.0/0 → IGW` route from `lab-cloud-web-public-rt`, watch external `curl` hang, re-add the route, watch it recover.
- Missing SG inbound 80: revoke the `tcp/80` rule, capture the `Connection refused` / timeout from outside, re-authorize, capture the recovery.
- `MapPublicIpOnLaunch = false`: launch a sibling test instance into the same subnet with auto-assign disabled and show that it has no `PublicIpAddress`.

> The reproduced case must be fully **reset** before Phase 6 cleanup so the SG/route tables end in the locked Phase 1/2 state.

### 3.2 Author `docs/troubleshooting.md`
Use exactly this structure (one `## Case N — <short title>` per issue):

```markdown
# Troubleshooting Report — 06-1 Cloud Lab

> Required by `docs/subject.md` §2.3. Each case follows the
> **symptom → hypothesis → verification → action → result → prevention** template
> mandated by subject §3·4.

## Case 1 — <short title, e.g. "External /health hangs while local /health returns 200">

### 1. Symptom
<exact command, exact error or unexpected output, timestamp if available>

### 2. Hypothesis
<at least one named candidate cause; if more than one, list and rank>

### 3. Verification
<commands run to narrow down; what each ruled in or out; evidence file paths>

### 4. Action
<minimal change made; quoted CLI / console step; what was NOT changed and why>

### 5. Result
<post-action command output proving the symptom is gone; evidence file path>

### 6. Prevention
<what to do during initial setup to never hit this again; cross-link to plan.md §X>
```

### 3.3 Evidence
- Reference at least one file under `docs/evidence/`. Reuse Phase 1–3 evidence (`05a-route-table.png`, `05-sg-inbound.png`, `01b-curl-verbose.txt`) where it fits.
- If the case needs new evidence, capture it under `docs/evidence/` with a stable name (e.g. `08-route-missing.png`, `09-journalctl-nginx.txt`). Do **not** scatter screenshots elsewhere.

### 3.4 Worked example (template-only — replace with real case)

```markdown
## Case 1 — External /health hangs; local /health is 200

### 1. Symptom
From learner laptop:
```
$ curl -i http://203.0.113.42/health
curl: (28) Failed to connect to 203.0.113.42 port 80 after 75001 ms: Connection timed out
```
From inside the instance (same minute, same IP):
```
$ curl -i http://localhost/health
HTTP/1.1 200 OK
...
OK
```

### 2. Hypothesis
Both candidates would explain the asymmetry:
1. Security Group inbound `tcp/80` was created on the wrong source CIDR (or missing).
2. Public route table is not associated with `lab-cloud-web-public-subnet`, so inbound packets have no path even though the SG is open.

### 3. Verification
- `aws ec2 describe-security-groups --filters Name=group-name,Values=lab-web-sg` shows only inbound 22 — no 80 rule. Hypothesis 1 confirmed.
- `aws ec2 describe-route-tables --filters Name=association.subnet-id,Values=<subnet-id>` returns the correct route table with `0.0.0.0/0 → igw-…` — Hypothesis 2 ruled out.
- Evidence: `docs/evidence/05-sg-inbound.png` (captured before the fix shows two rules; here it shows only the SSH rule).

### 4. Action
Console → EC2 → Security Groups → `lab-web-sg` → Inbound rules → Edit → Add rule: HTTP, TCP/80, `0.0.0.0/0`. Save. **No other rule was touched** — outbound and SSH remain unchanged.

### 5. Result
From learner laptop, 5 seconds after save:
```
$ curl -i http://203.0.113.42/health
HTTP/1.1 200 OK
...
OK
```
Re-captured `docs/evidence/05-sg-inbound.png` now shows both rules.

### 6. Prevention
Create the SG **before** launching the EC2 with rules from `docs/plan.md` §4.4, not after the instance is up. The plan now lists this rule in Phase 2 §3.3 as the second action in the SG creation block.
```

> The above is illustrative. Replace with the case you actually hit; **do not** copy this case verbatim into the report if it did not happen.

---

## 4. Files Touched

| File | Action |
| ---- | ------ |
| `06-1/docs/troubleshooting.md` | create (one or more cases) |
| `06-1/docs/evidence/08-*.png` or `09-*.txt` | create (only if not already covered by Phase 1–3 evidence) |
| `06-1/README.md` | edit (add link to `docs/troubleshooting.md` in Deliverables section) |

No AWS resources are modified in this phase (the architecture must end this phase in the same locked state as the end of Phase 2; any reproduction case must reset).

---

## 5. Acceptance Criteria

- [ ] `06-1/docs/troubleshooting.md` exists, contains **at least one** `## Case N` block, and every block has **all six** fields filled (symptom, hypothesis, verification, action, result, prevention) — no `<…>` placeholders left.
- [ ] Each case references at least one concrete evidence file path under `docs/evidence/`; every referenced file exists.
- [ ] Every command quoted in the report is reproducible: it includes the actual IP / resource name as used in this lab, not `<public-ip>` placeholders.
- [ ] If the case was a reproduction (§3.1 B), the resource state at the end of this phase matches the locked Phase 1/2 state (`describe-security-groups`, `describe-route-tables` outputs unchanged).
- [ ] `README.md` Deliverables section links to `docs/troubleshooting.md`.
- [ ] No `AdministratorAccess` was attached during the diagnostic loop (subject §4.4 + `plan.md` §8 risk row).
- [ ] No SG rule allowing `0–65535` from `0.0.0.0/0` was used at any point during diagnosis (the temptation called out in `plan.md` §8).

---

## 6. Commit

```
docs: add troubleshooting report with one full cycle
```

One commit per `.cursorrules` §6 (Logical Commit Unit). Bundles `troubleshooting.md`, any new evidence files, and the README link update.

---

## 7. Risks / Notes

- **Don't widen the SG to debug**. The first reflex when an external check fails is to add `0–65535` from `0.0.0.0/0`. Subject §4.3 forbids it, and the report is the worse for it — if "all ports open" makes it work, you have not localized the bug. Use `nc -vz` and `curl -v` from inside and outside to triangulate the **specific** port + direction.
- **Negative evidence counts**. If the verification step ruled a hypothesis **out**, say so — that's exactly the loop subject §3·4 wants to see.
- A real case is always stronger than a reproduced one. Even a minor "nginx -t complained about duplicate default_server" is fine.
- If you reproduced a case (§3.1 B), screenshot **both** the broken and the fixed state. Submit the broken-state screenshot in §1 Symptom / §3 Verification, and the fixed-state screenshot in §5 Result.
- The "prevention" field is not a postscript — it is graded. Tie it back to a `plan.md` §X section that, if followed, would have avoided the bug.

---

## 8. Definition of Done

- Subject §2.3 deliverable is met: `docs/troubleshooting.md` with at least one full **symptom → hypothesis → verification → action → result → prevention** case backed by evidence.
- The architecture is in the same locked state as the end of Phase 2/3, ready for Phase 6 cleanup.
- Phase 5 closes one of the four subject §2 deliverables. After Phase 6, all four are done.
