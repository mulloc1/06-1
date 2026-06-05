# Phase 7 (Optional) — Bonus Tasks (HTTPS + Docker)

> Parent plan: [`docs/plan.md`](../plan.md) §6 Phase 7
> Detailed plan: [`docs/bonus_plan.md`](../bonus_plan.md)
> Subject reference: [`docs/subject.md`](../subject.md) §5

Phase 7 is **optional** and only begins after Phases 0–6 are committed, the four subject §2 deliverables are submitted, and the core stack is either still running or rebuilt from the same locked decisions in `plan.md` §2. Per `.cursorrules` §4 (YAGNI) and `plan.md` §6, none of the bonus items are required to satisfy the assignment — they layer on top of a working core without changing core decisions.

The full per-task design lives in [`bonus_plan.md`](../bonus_plan.md). This file is the **executive summary** so the phased sequence in `plans/` stays consistent with the core plan.

---

## 1. Goal

Add the two optional features from subject §5 without breaking the four core deliverables:

| Item | Subject §5 text | Sub-phase in `bonus_plan.md` |
| --- | --- | --- |
| HTTPS via Let's Encrypt | Free subdomain (or owned domain) + HTTPS with Let's Encrypt | `bonus_plan.md` §4 (Bonus 1) |
| Docker on EC2 | Install Docker on EC2 and run the web service in a container | `bonus_plan.md` §5 (Bonus 2) |

Each bonus item is a separate commit; `README.md` and the architecture diagram are updated last.

---

## 2. Preconditions

Do not start Phase 7 unless **all** of the following are true:

- [ ] Phases 0–6 are committed and the four subject §2 deliverables are present (`docs/architecture.png`, README with external-access proof, `docs/troubleshooting.md`, `docs/cleanup-checklist.md`).
- [ ] The core stack from `plan.md` §4 is either still running in `ap-northeast-2` **or** can be re-provisioned from the locked decisions in `plan.md` §2 (Phases 1–2 are repeatable from the docs).
- [ ] The lab IAM user `lab-cloud-web` is still active **or** has been recreated with the same `lab-cloud-web-policy` (Phase 0 §3.2–§3.3).
- [ ] Branching strategy decided: per `.cursorrules` §4 (YAGNI), bonus commits live in **separate commits** and may go on a `bonus/*` branch so the core mission grading scope is untouched.

If any item is false, finish that core item first — `bonus_plan.md` does not back-fill anything.

---

## 3. Sub-phase Map

`bonus_plan.md` is structured around two sub-phases plus a docs sub-phase. Each maps to one commit:

### Sub-phase B1 — HTTPS (`bonus_plan.md` §4)

- Allocate one **Elastic IP**, associate it with the EC2 instance.
- Create the free DuckDNS subdomain and point an **A record** at the Elastic IP.
- Open `tcp/443` from `0.0.0.0/0` on `lab-web-sg`; keep `80/tcp` open (used for the ACME challenge and the HTTP→HTTPS redirect).
- Install certbot via `dnf` and issue the cert with the **HTTP-01 standalone** flow.
- Wire `certbot.timer` for automatic renewal with `--deploy-hook 'docker restart nginx-web'`.
- Capture `docs/evidence/10-https-health.png`, `11-browser-padlock.png`, `13-cert-issued.txt`, `14-renewal-dry-run.txt`, `15-https-redirect.png`.
- Commit: `docs: add https via letsencrypt and elastic ip`

### Sub-phase B2 — Docker (`bonus_plan.md` §5)

- Install Docker Engine on the existing EC2 via `dnf install -y docker`; enable `--now`.
- Add `ec2-user` to the `docker` group (re-login to pick up the group).
- Stop and disable the host Nginx (its surface is replaced by the container; ports `80/443` must be free).
- Run `nginx:1.27-alpine` as `nginx-web` with `--restart unless-stopped`, bind-mounting `/opt/nginx-web/conf.d/default.conf` (HTTP redirect + HTTPS server + `/health`) and `/etc/letsencrypt` (read-only).
- Capture `docs/evidence/12-docker-ps.png` and re-capture `10-https-health.png` against the container.
- Commit: `docs: run nginx in docker container on ec2`

### Sub-phase B3 — Bonus docs (`bonus_plan.md` §3)

- Append a **Bonus Features** section to `06-1/README.md`: HTTPS URL, port mapping, container image + run method, ≥ 2 verification screenshots.
- Re-export the architecture diagram to show the HTTPS path (`:443` arrow), the Elastic IP block, and the Docker container hosting Nginx on the EC2 → overwrite `docs/architecture.png` (or save as `docs/architecture-bonus.png` if grading wants the original preserved — choose one and document the choice in the README).
- Extend `docs/cleanup-checklist.md` with the new rows: **Elastic IP**, **DuckDNS A record**, **certbot timer**, **Docker container & volumes**, **Docker images**, **`/etc/letsencrypt/`**.
- If any HTTPS/Docker issue surfaced during B1/B2 (e.g. ACME 80-port collision, "permission denied" before group membership took effect), append a **second case** to `docs/troubleshooting.md`.
- Commit: `docs: update readme, diagram, and cleanup for bonus`

---

## 4. Files Touched (Summary)

See [`bonus_plan.md` §3](../bonus_plan.md) for the full table. Highlights:

| File | Change |
| --- | --- |
| `06-1/README.md` | append **Bonus Features** section |
| `docs/architecture.png` | re-export to show HTTPS + Docker layers |
| `docs/troubleshooting.md` | optional second case |
| `docs/cleanup-checklist.md` | add bonus rows |
| `docs/bonus/nginx-default.conf` | new — Nginx config bind-mounted into container |
| `docs/bonus/setup-notes.md` | new — linear command log for re-runs |
| `docs/evidence/10-…` through `15-…` | new — bonus verification screenshots |

AWS-side additions: one **Elastic IP**, one **inbound `tcp/443`** SG rule, one **DuckDNS A record** (external to AWS).

---

## 5. Acceptance Criteria

- [ ] `curl -i https://<learner>.duckdns.org/health` returns `HTTP/2 200` and body `OK`; the cert is valid (no `--insecure` flag needed).
- [ ] `curl -i http://<learner>.duckdns.org/health` returns `301` redirecting to the `https://` URL.
- [ ] Browser at `https://<learner>.duckdns.org` shows a valid padlock; URL bar starts with `https://`.
- [ ] On the instance: `docker ps --filter name=nginx-web` shows the container `Up`, ports `0.0.0.0:80->80/tcp, 0.0.0.0:443->443/tcp`, image `nginx:1.27-alpine`.
- [ ] On the instance: `sudo systemctl is-active nginx` returns `inactive` (host Nginx is replaced by the container).
- [ ] `sudo certbot renew --dry-run` succeeds and logs the `docker restart nginx-web` deploy hook.
- [ ] All 6 new evidence files exist under `docs/evidence/` (`10-https-health.png`, `11-browser-padlock.png`, `12-docker-ps.png`, `13-cert-issued.txt`, `14-renewal-dry-run.txt`, `15-https-redirect.png`).
- [ ] `06-1/README.md` Bonus Features section is present with URL, port mapping, image name, run method, and ≥ 2 screenshots (subject §5 requirement).
- [ ] `docs/cleanup-checklist.md` has explicit rows for Elastic IP, DuckDNS A record, certbot timer, container, image, and `/etc/letsencrypt/`.
- [ ] **No** SG rule allowing `0–65535` from `0.0.0.0/0` exists; only `80`, `443` (from `0.0.0.0/0`) and `22` (from `<learner-IP>/32`).
- [ ] **No** new IAM permissions were added to `lab-cloud-web` (HTTPS + Docker do not require new AWS API calls per `bonus_plan.md` §2).

---

## 6. Commits

Per `.cursorrules` §6 (Logical Commit Unit), three commits — one per sub-phase:

```
docs: add https via letsencrypt and elastic ip
docs: run nginx in docker container on ec2
docs: update readme, diagram, and cleanup for bonus
```

---

## 7. Risks / Notes

- **ACME 80-port collision**: the standalone HTTP-01 challenge needs port 80. Either stop the host Nginx briefly during issuance, or switch to the webroot challenge later — the locked decision in `bonus_plan.md` §2 is the standalone flow with a one-time stop.
- **Docker group membership** does not take effect in the **current** shell. The first `docker ps` after `usermod -aG docker ec2-user` will fail with "permission denied" until SSH re-login. Document if you hit this in a `troubleshooting.md` Case 2.
- **Cert path inside container**: the bind-mount `/etc/letsencrypt → /etc/letsencrypt` must be read-only. A renewal that fails because the container holds an open file handle is rare but recoverable; the `--deploy-hook 'docker restart nginx-web'` flow avoids it.
- **Elastic IP charges** while detached. Once the bonus phase teardown runs, **release** the EIP (don't just disassociate).
- **DuckDNS expiry**: free DuckDNS subdomains expire after 30 days of inactivity. For a one-shot lab this doesn't matter; if the bonus is graded weeks later, re-ping DuckDNS to keep the record alive.
- **The four core deliverables must continue to validate** after bonus is applied. If the bonus changes the architecture diagram, keep the original PNG as `docs/evidence/architecture-core.png` (or version the file in commit history) so subject §2.1 evidence is recoverable.
- **Cleanup order** for bonus: stop and `docker rm` the container → release Elastic IP → remove DuckDNS record → disable `certbot.timer` → `rm -rf /etc/letsencrypt/` → remove the `tcp/443` SG rule. Then the core teardown order from Phase 6 still applies.

---

## 8. Definition of Done

- HTTPS works against the free DuckDNS subdomain with a Let's Encrypt cert; renewal dry-run passes.
- The web service runs in a Docker container on the same EC2 instance, exposing the same `GET /health → 200 OK` contract as core.
- README, architecture diagram, troubleshooting report (if extended), and cleanup checklist all reflect the bonus state.
- The three bonus commits are isolated from the core commit history so subject §2 grading scope is unchanged.
- The lab is still tear-down-ready: Phase 6's order plus the bonus rows in `cleanup-checklist.md` will leave zero billable resources behind.
