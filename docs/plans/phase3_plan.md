# Phase 3 — External Access Proof

> Parent plan: [`docs/plan.md`](../plan.md) §6 Phase 3
> Subject reference: [`docs/subject.md`](../subject.md) §2.2, §4.5

This phase produces the **external-access deliverable** required by subject §2.2: at least one screenshot proving the public web service is reachable from the internet, plus an updated `README.md` declaring the chosen verification method (locked to **Method B — `GET /health`** in `plan.md` §2 decisions table, with Method A as supporting evidence). No infrastructure changes happen here — this phase only consumes what Phase 2 produced.

---

## 1. Goal

- From the learner's laptop (not the instance), confirm `curl -i http://<public-ip>/health` returns `HTTP/1.1 200 OK` with body `OK`, and capture the terminal as `docs/evidence/01-curl-health.png`.
- Open a browser to `http://<public-ip>` and screenshot the rendered Nginx page (with the Phase 2 custom heading) as `docs/evidence/02-browser-root.png`.
- Update `06-1/README.md` with the public IP, the chosen verification method, the two screenshots, and a one-paragraph "How to verify" section so a reviewer can re-run the check.

---

## 2. Scope (In / Out)

**In scope**
- Two external HTTP checks against `<public-ip>` (`/health` via `curl`, `/` via browser).
- README updates: public URL/IP, verification method, embedded screenshots.
- Negative checks documented inline in `README.md` if cheap (e.g. show that HTTPS is **not** offered in core scope — that's the bonus phase).
- Capturing `curl -v` output to a text file under `docs/evidence/` **only if** Phase 5 (Troubleshooting Report) intends to quote it; otherwise skip.

**Out of scope**
- Any AWS resource change. If `/health` returns non-200, the fix is diagnosed and applied as part of Phase 5 (Troubleshooting Report), then this phase is re-run.
- HTTPS. TLS lives in `bonus_plan.md` Phase B1.
- DNS / domain name. Plain IP is the deliverable.

---

## 3. Tasks

### 3.1 Retrieve the public IP
- From the learner laptop:
  ```bash
  aws ec2 describe-instances --profile lab --region ap-northeast-2 \
    --filters Name=tag:Name,Values=lab-cloud-web-ec2 \
    --query 'Reservations[0].Instances[0].PublicIpAddress' --output text
  ```
- Record the IP for the README. Confirm it is the same address used for the Phase 2 SSH.

### 3.2 Method (B) primary: `curl /health`
- From the learner laptop:
  ```bash
  curl -i http://<public-ip>/health
  ```
  Expected:
  ```
  HTTP/1.1 200 OK
  Server: nginx/...
  Content-Type: text/plain
  ...

  OK
  ```
- Capture the terminal frame (showing the typed command **and** the full response headers + body) → `docs/evidence/01-curl-health.png`.

### 3.3 Method (A) supporting: browser
- Open a browser to `http://<public-ip>`. The page should render the Phase 2 custom heading (`06-1 cloud lab — lab-cloud-web-ec2`).
- Confirm the URL bar shows `http://`, **not** `https://`, and that there is no padlock — core scope is HTTP only.
- Screenshot the **full browser window** (URL bar + rendered page) → `docs/evidence/02-browser-root.png`.

### 3.4 README update
- Edit `06-1/README.md`. Replace the placeholder "Public URL & Verification" section with concrete content:

  ```markdown
  ## Public URL & Verification

  - **Public URL**: `http://<public-ip>/` (HTTP, port 80, no DNS in core scope)
  - **Health endpoint**: `http://<public-ip>/health` → `200 OK` with body `OK`
  - **Chosen verification method**: **(B)** `GET /health` (deterministic, scriptable). Method (A) browser screenshot is included as supporting evidence.

  ### How to verify

  ```bash
  curl -i http://<public-ip>/health
  ```

  ![curl /health 200 OK](docs/evidence/01-curl-health.png)
  ![browser at http://<public-ip>](docs/evidence/02-browser-root.png)

  > The instance does not offer HTTPS in core scope. TLS is intentionally deferred to `docs/bonus_plan.md`.
  ```

- Replace every literal `<public-ip>` with the actual IPv4 from step 3.1.

### 3.5 Optional: capture `curl -v` for troubleshooting
- If Phase 5 plans to quote header-level detail (TCP handshake, TLS attempt, redirect chains), run:
  ```bash
  curl -v http://<public-ip>/health 2>&1 | tee docs/evidence/01b-curl-verbose.txt
  ```
- Skip this if the Phase 5 case will be diagnosed from CloudWatch / `journalctl` instead — don't generate evidence that nothing references.

---

## 4. Files Touched

| File | Action |
| ---- | ------ |
| `06-1/README.md` | edit (Public URL & Verification section) |
| `06-1/docs/evidence/01-curl-health.png` | create |
| `06-1/docs/evidence/02-browser-root.png` | create |
| `06-1/docs/evidence/01b-curl-verbose.txt` | create (optional, only if used by Phase 5) |

No AWS resources are created or modified.

---

## 5. Acceptance Criteria

- [ ] `curl -i http://<public-ip>/health` from the learner laptop returns `HTTP/1.1 200 OK` and body `OK`.
- [ ] `curl -i http://<public-ip>/` returns `HTTP/1.1 200 OK` and the body contains the Phase 2 custom heading string.
- [ ] Browser at `http://<public-ip>` renders the custom heading and the URL bar shows `http://` (not `https://`).
- [ ] `06-1/README.md` declares chosen method (B), lists the public IP, embeds both screenshots, and includes the `curl` snippet for reviewers to re-run.
- [ ] Both screenshots exist under `docs/evidence/` with the locked filenames; embedded paths in README resolve.
- [ ] If `01b-curl-verbose.txt` was created, it is referenced from either `README.md` or `troubleshooting.md`; otherwise it is **not** committed.
- [ ] No SG rule, route table, or subnet was changed in this phase (`git diff` shows changes only under `06-1/README.md` and `06-1/docs/evidence/`).

---

## 6. Commit

```
docs: verify external http access with /health and browser
```

One commit per `.cursorrules` §6 (Logical Commit Unit). Bundles the README edit and both screenshots — they are meaningless apart.

---

## 7. Risks / Notes

- If `/health` works locally (Phase 2) but **not** externally, the failure is almost always one of:
  1. SG inbound HTTP rule missing or scoped tighter than `0.0.0.0/0`.
  2. Subnet `MapPublicIpOnLaunch = false` and the instance has no public IP.
  3. Route table missing `0.0.0.0/0 → IGW` or not associated with the subnet.
  4. Corporate firewall on the learner's network blocking outbound 80. Test from a phone hotspot before assuming AWS-side bug.
- The browser screenshot must include the URL bar; otherwise a reviewer cannot verify the IP/HTTP scheme matches the README.
- Do **not** retake screenshots after a stop/start cycle that rotates the public IP — either retake **all** Phase 3 evidence with the new IP **and** update the README, or never stop the instance until Phase 6.
- If Phase 5 ends up not needing verbose curl evidence, delete `01b-curl-verbose.txt` before commit. `.cursorrules` §4 — no unreferenced artifacts.

---

## 8. Definition of Done

- The README's "Public URL & Verification" section is complete and self-contained: a reviewer with no other context can copy the `curl` line and reproduce the `200 OK`.
- The two locked screenshots are committed under `docs/evidence/`.
- This phase is the **primary subject §2.2 deliverable**; with Phase 4 it covers two of the four subject §2 deliverables (the other two are Phases 5 and 6).
