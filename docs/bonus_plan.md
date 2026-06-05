# Cloud Infrastructure Bonus Implementation Plan (bonus_plan.md)

This document plans the **bonus tasks** in `docs/subject.md` §5. It assumes the core mission (`docs/plan.md` Phases 0–6) is **done, verified, and either still running or rebuilt from the same locked decisions**. Per `.cursorrules` §4 (YAGNI), we keep additions **minimal** and only extend the stack where the existing topology already fits.

Subject §5 lists two optional items:

| Item | Subject text |
| ---- | ------------ |
| **Bonus 1 — HTTPS** | Free subdomain (or owned domain) + HTTPS via Let's Encrypt |
| **Bonus 2 — Docker on EC2** | Install Docker on EC2 and run the web service in a container |

---

## 1. Goal Summary

- Add the two bonus features **without breaking** the four core deliverables (architecture diagram, external-access proof, troubleshooting report, cleanup checklist) locked in `plan.md` §2 / §6.
- Keep the **same VPC / subnet / IGW / EC2** layout from core; the bonus only **layers on top**: a TLS cert + an HTTPS SG rule + an Elastic IP + DNS + Docker on the existing instance.
- Run the web service via **Docker** so that the existing `GET /health` contract from `plan.md` §4.3 still returns `200 OK`; the host's stock Nginx is **replaced** by an Nginx container with the same surface.
- Bonus features ship as a **separate set of commits** so the core grading scope is untouched (`.cursorrules` §6 Logical Commit Unit).
- Keep IAM **as narrow as it was for core**; HTTPS and Docker do not require new IAM actions on the lab user.

---

## 2. Locked Decisions

Decisions for items left free by subject §5 (which subdomain provider, which certbot flow, which container image, port mapping, certificate location, etc.) and for choices that would be expensive to reverse later.

| Item | Decision | Rationale |
| ---- | -------- | --------- |
| Domain source | **Free subdomain** on **DuckDNS** (`<learner>.duckdns.org`) | Free, instant, no registrar account; sufficient to issue a Let's Encrypt cert |
| Stable IP | Allocate **one Elastic IP** and associate with the EC2 instance | Public IPv4 must not change between cert issuance and renewals; EIP is the simplest fix |
| DNS record type | **A record** → Elastic IP | DuckDNS supports A records; no need for AAAA in this scope |
| TLS provider | **Let's Encrypt** via **certbot** with the **standalone HTTP-01** challenge during issuance | Avoids configuring a webroot before the container is up; uses port 80 briefly while Nginx is stopped |
| Certbot install | `dnf install -y certbot` on Amazon Linux 2023 | Distro package; no `pip`/snap layer (.cursorrules §4 minimal) |
| Cert storage | `/etc/letsencrypt/live/<learner>.duckdns.org/{fullchain.pem,privkey.pem}` (default) mounted **read-only** into the container | Single source of truth; container can read but not modify |
| TLS renewal | `systemd` timer `certbot.timer` (ships with the package) → on success, **`docker restart nginx-web`** via a `--deploy-hook` | Automatic 60-day-ahead renewal; container reloads cert with one restart |
| Security Group — HTTPS | Add inbound `tcp/443` from `0.0.0.0/0`; keep existing `80/tcp` from `0.0.0.0/0` (used for redirect + ACME) and `22/tcp` from `<learner-IP>/32` | Subject §4.3 still forbids all-ports-from-anywhere; only one new rule |
| HTTP → HTTPS | Server block on `:80` returns `301 https://$host$request_uri` for all paths **except** `/.well-known/acme-challenge/` (left open if a future webroot flow is needed) | Standard hardening; preserves ACME path |
| Container runtime | **Docker Engine** from Amazon Linux 2023 `docker` package | Simpler than installing `containerd`+CRI alone; satisfies subject §5 Bonus 2 |
| Docker management user | `ec2-user` added to the `docker` group so `docker` runs without `sudo` after re-login | Reduces typos; root-equivalent risk acknowledged in §10 |
| Container image | **`nginx:1.27-alpine`** (public image on Docker Hub) | Small, official, predictable; satisfies subject §5 "your prior mission image or a public image" |
| Container name | `nginx-web` | Single name referenced in commands, scripts, and logs |
| Port mapping | Host `80:80` and `443:443` mapped 1:1 to the container | Subject §5 requires documenting the mapping; 1:1 keeps the SG rules and `/health` URL identical to core |
| Container config source | **Bind-mount** `/opt/nginx-web/conf.d/default.conf` (HTTP+HTTPS server blocks, `/health`) and `/etc/letsencrypt` (certs) | No custom image build needed; config edits don't require rebuilds |
| Container restart policy | `--restart unless-stopped` | Survives reboots and Docker daemon restarts during cert renewal |
| Logs | `docker logs nginx-web` + bind-mounted `/var/log/nginx-web/` for `access.log`/`error.log` | Same evidence pattern as core (paths recorded in README) |
| Verification method (still) | Method (B): `GET /health` over **HTTPS** is the new primary; method (A) browser visit is the secondary | Same contract as `plan.md` §5.1, just on `https://` |
| Out of scope for this phase | HTTP/2 push, OCSP stapling tuning, multiple subdomains, automated container registry, ECR, ALB, ECS, CDN | YAGNI; subject §5 asks for one HTTPS subdomain and one Dockerized service |

> All other choices follow `docs/plan.md` §2 (region, AMI, instance type, IAM user, VPC CIDR, AZ, key pair, etc.). This file does **not** override any decision locked there.

---

## 3. Affected Files (Minimal Footprint)

Edit existing docs rather than introduce new layers. New files appear only where an existing one cannot own the new responsibility.

| File | Change |
| ---- | ------ |
| `06-1/README.md` | Append **Bonus Features** section: domain, HTTPS URL, port mapping, container image, ≥ 2 verification screenshots |
| `docs/architecture.png` | Re-export to show HTTPS path (`:443` arrow), Elastic IP block, and the Docker container hosting Nginx on the EC2 |
| `docs/troubleshooting.md` | Append a second case if any HTTPS/Docker issue arises (e.g. ACME 80-port collision, group membership not active in current shell) |
| `docs/cleanup-checklist.md` | Add rows for **Elastic IP**, **DuckDNS A record**, **certbot cron/timer**, **Docker container & volumes**, **Docker images**, **`/etc/letsencrypt/`** |
| `docs/evidence/` *(new files)* | `10-https-health.png`, `11-browser-padlock.png`, `12-docker-ps.png`, `13-cert-issued.txt`, `14-renewal-dry-run.txt`, `15-https-redirect.png` |
| `docs/bonus/nginx-default.conf` *(new)* | The Nginx config bind-mounted into the container (HTTP redirect + HTTPS server + `/health`); committed as a reference artifact |
| `docs/bonus/setup-notes.md` *(new)* | Linear command log for HTTPS + Docker steps so the lab can be re-run in one sitting |

> Two new files (`docs/bonus/nginx-default.conf`, `docs/bonus/setup-notes.md`) are justified: the Nginx config is the **single source of truth** the running container references, and the setup-notes file isolates one-time commands from the deliverable docs so the four core docs stay unchanged in structure (.cursorrules §5 SRP).

---

## 4. HTTPS (subject §5 — Bonus 1)

### 4.1 DNS + Stable IP

1. In the AWS console, allocate one **Elastic IP** and **associate** it with the existing EC2 instance. (Charge: free while attached; tear down in cleanup.)
2. In the DuckDNS dashboard, set the subdomain's **A record** to the Elastic IP value.
3. Verify: `dig +short <learner>.duckdns.org` → Elastic IP.

### 4.2 Open 443 on the Security Group

- Add one inbound rule: `tcp/443` from `0.0.0.0/0`.
- Do **not** widen any other rule. Final inbound set is `80/tcp` from `0.0.0.0/0`, `443/tcp` from `0.0.0.0/0`, `22/tcp` from `<learner-IP>/32`.

### 4.3 Issue the Certificate (standalone HTTP-01)

```
sudo dnf install -y certbot
sudo docker stop nginx-web 2>/dev/null || sudo systemctl stop nginx 2>/dev/null
sudo certbot certonly \
  --standalone \
  --non-interactive --agree-tos \
  -m <learner-email> \
  -d <learner>.duckdns.org
```

- Cert files land at `/etc/letsencrypt/live/<learner>.duckdns.org/`.
- Capture stdout to `docs/evidence/13-cert-issued.txt`.

### 4.4 Nginx HTTPS Config (`docs/bonus/nginx-default.conf`)

```nginx
server {
    listen 80 default_server;
    server_name <learner>.duckdns.org;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name <learner>.duckdns.org;

    ssl_certificate     /etc/letsencrypt/live/<learner>.duckdns.org/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/<learner>.duckdns.org/privkey.pem;

    location / {
        root  /usr/share/nginx/html;
        index index.html;
    }

    location = /health {
        access_log off;
        default_type text/plain;
        return 200 "OK\n";
    }
}
```

### 4.5 Renewal

- Enable the package's timer: `sudo systemctl enable --now certbot.timer`.
- Add a **deploy hook** that restarts the container after a successful renewal:

```
sudo tee /etc/letsencrypt/renewal-hooks/deploy/restart-nginx-web.sh >/dev/null <<'EOF'
#!/usr/bin/env bash
docker restart nginx-web
EOF
sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/restart-nginx-web.sh
```

- Verify with `sudo certbot renew --dry-run`; capture output to `docs/evidence/14-renewal-dry-run.txt`.

### 4.6 Acceptance

- `curl -i https://<learner>.duckdns.org/health` → `200 OK` with body `OK`; cert chain valid (no `-k` flag needed).
- `curl -i http://<learner>.duckdns.org/health` → `301` to `https://...`.
- Browser shows a padlock on `https://<learner>.duckdns.org` (screenshot `11-browser-padlock.png`).

---

## 5. Docker on EC2 (subject §5 — Bonus 2)

### 5.1 Install Docker

```
sudo dnf install -y docker
sudo systemctl enable --now docker
sudo usermod -aG docker ec2-user
# log out and back in so group membership applies
docker --version
```

- Stop and disable the host's stock Nginx so port 80/443 are free for the container:

```
sudo systemctl disable --now nginx || true
```

### 5.2 Prepare Bind-Mount Layout

```
sudo mkdir -p /opt/nginx-web/conf.d /opt/nginx-web/html /var/log/nginx-web
sudo cp docs/bonus/nginx-default.conf /opt/nginx-web/conf.d/default.conf
sudo cp -a /usr/share/nginx/html/. /opt/nginx-web/html/   # carry over the customized index.html
```

### 5.3 Run the Container

```
docker run -d \
  --name nginx-web \
  --restart unless-stopped \
  -p 80:80 -p 443:443 \
  -v /opt/nginx-web/conf.d:/etc/nginx/conf.d:ro \
  -v /opt/nginx-web/html:/usr/share/nginx/html:ro \
  -v /etc/letsencrypt:/etc/letsencrypt:ro \
  -v /var/log/nginx-web:/var/log/nginx \
  nginx:1.27-alpine
```

- Capture `docker ps` → `docs/evidence/12-docker-ps.png` (shows ports, image, container name).

### 5.4 Internal & External Verification (subject §5 Bonus 2 table)

| Check | Command | Expected |
| ----- | ------- | -------- |
| Required (internal) | `curl -i http://localhost/health` on the instance | `200 OK`, body `OK` |
| Required (internal — HTTPS) | `curl -ki https://localhost/health` on the instance | `200 OK`, body `OK` |
| Required (external) | `curl -i https://<learner>.duckdns.org/health` from outside | `200 OK`, body `OK` |
| HTTP redirect | `curl -i http://<learner>.duckdns.org/health` from outside | `301` → `https://...` |
| Browser | open `https://<learner>.duckdns.org` | padlock; custom page renders |

### 5.5 README Documentation Block

Append to `06-1/README.md` (subject §5 Bonus 2 explicitly requires these fields):

- **Image name and run method**: `nginx:1.27-alpine`, started with the `docker run` command in §5.3.
- **Port mapping**: host `80 → container 80`, host `443 → container 443`.
- **Verification screenshots** (≥ 2): `10-https-health.png` (`curl -i https://.../health`), `11-browser-padlock.png`, `12-docker-ps.png`.

---

## 6. Phased Plan

Each phase = **one logical change = one commit** (`.cursorrules` §6). Conventional Commits prefix.

### Phase B0 — Branch off & docs

- Branch off (e.g. `bonus`) from the core mission commit.
- Add this file as `docs/bonus_plan.md`.
- Commit: `docs: plan bonus tasks (https, docker)`

### Phase B1 — Stable IP & DNS

- Allocate Elastic IP, associate with the instance, point the DuckDNS A record at it.
- Verify with `dig +short`; capture the value.
- Commit: `docs: associate elastic ip and point duckdns subdomain`

### Phase B2 — Open 443 + Issue Let's Encrypt cert

- Add the `443/tcp` SG rule; install certbot; stop the host Nginx; issue the cert with `--standalone`; capture issuance output.
- Commit: `docs: enable https with lets encrypt standalone certificate`

### Phase B3 — Docker install & containerize Nginx

- Install Docker; disable host Nginx; prepare bind-mount dirs; run `nginx:1.27-alpine` with the §5.3 command; capture `docker ps` and `curl` outputs.
- Commit: `docs: replace host nginx with dockerized nginx container`

### Phase B4 — TLS auto-renewal hook

- Enable `certbot.timer`; install the `deploy` hook that restarts `nginx-web`; run `certbot renew --dry-run` and capture the output.
- Commit: `docs: wire certbot renewal hook to restart nginx container`

### Phase B5 — Diagram, README, evidence

- Re-export `docs/architecture.png` to include EIP, port 443, container; append the "Bonus Features" section to `06-1/README.md` with the image / mapping / screenshots block; commit reference `nginx-default.conf` and `setup-notes.md` under `docs/bonus/`.
- Commit: `docs: document bonus features (https, docker) in readme and diagram`

### Phase B6 — Extended cleanup checklist

- Add Elastic IP, DuckDNS A record, certbot timer, Docker container + image + volumes, `/etc/letsencrypt/` to `docs/cleanup-checklist.md`; ensure ordering is **detach EIP → release EIP → terminate instance** so AWS does not bill an unattached EIP between steps.
- Commit: `docs: extend cleanup checklist for https and docker resources`

---

## 7. Verification Strategy

Same posture as `plan.md` §7 (no automated suite required; manual checklist). New checks layered on top of the core checklist:

- [ ] **DNS**: `dig +short <learner>.duckdns.org` returns the Elastic IP.
- [ ] **EIP**: Elastic IP shows **associated** with the EC2 instance in the console; not idle.
- [ ] **SG**: only `80/443` from `0.0.0.0/0` and `22` from `<learner-IP>/32`; still no `0–65535` rule.
- [ ] **Cert issuance**: `13-cert-issued.txt` shows "Successfully received certificate"; `/etc/letsencrypt/live/<learner>.duckdns.org/fullchain.pem` exists.
- [ ] **HTTPS health**: `curl -i https://<learner>.duckdns.org/health` returns `200 OK`, body `OK`, with a valid (non-expired) chain — no `-k` required.
- [ ] **HTTP → HTTPS redirect**: `curl -i http://<learner>.duckdns.org/health` returns `301`.
- [ ] **Browser padlock**: screenshot `11-browser-padlock.png` shows a closed padlock and "Certificate is valid".
- [ ] **Docker**: `docker ps` lists `nginx-web` with `0.0.0.0:80->80/tcp, 0.0.0.0:443->443/tcp`; image is `nginx:1.27-alpine`.
- [ ] **Container survives reboot**: `sudo reboot`, then after ~1 minute `curl -i https://.../health` still returns `200`.
- [ ] **Renewal dry-run**: `14-renewal-dry-run.txt` shows "Congratulations, all simulated renewals succeeded".
- [ ] **Renewal hook**: after `sudo certbot renew --force-renewal --dry-run`, `journalctl -u certbot.service` shows the deploy hook ran without error (or the file is `+x` and reads correctly).
- [ ] **README**: contains the image name, exact `docker run` command (or a copy), port mapping table, and ≥ 2 verification screenshots.
- [ ] **Regressions**: all core checklist items in `plan.md` §7 still pass — `/health` over HTTP/localhost on the instance returns `200`, SSH still works, outbound `curl https://example.com` from the instance still returns `200`, IAM still has no admin.

---

## 8. Risks / Open Points

| Risk | Mitigation |
| ---- | ---------- |
| Port-80 collision during `certbot --standalone` | Stop the container/host Nginx before `certbot certonly`; restart after; this is captured in the §4.3 command sequence |
| Elastic IP idle charge | EIP is **only** billed while unattached; cleanup checklist ordering (detach → release **after** terminate) prevents an idle window if done carefully — alternatively release immediately after instance termination |
| Docker group membership not active in current shell | Log out and back in (or `newgrp docker`) before running `docker` without `sudo`; documented in `bonus/setup-notes.md` |
| DuckDNS rate limits / token rotation | Tokens are per-account and stable; if it changes, update the DuckDNS dashboard A record manually — no IAM impact |
| Let's Encrypt rate limits (5 certs / domain / week) | Avoid repeated `--force-renewal` during testing; the dry-run is rate-limit-free |
| `nginx:1.27-alpine` image tag drift | Pin to a specific minor tag (`1.27-alpine`) rather than `latest`; document the digest in the README if reproducibility matters |
| Cert renewal hook silently fails (container name typo) | Add a one-line `docker ps --filter name=nginx-web` smoke check inside the hook; non-zero exit surfaces in `journalctl` |
| Host vs container log paths confuse troubleshooting | Logs live at `/var/log/nginx-web/` on the host via bind-mount; documented in `bonus/setup-notes.md` |
| User membership in `docker` group ≈ root | Acknowledged trade-off; this is a lab account, not a production user; mentioned in README "Security Notes" |
| Architecture diagram drift | Update `architecture.png` once at the end of B5; do not let it lag commits B1–B4 |

---

## 9. Definition of Done

- The HTTPS subdomain `https://<learner>.duckdns.org` returns the same `/health 200 OK` contract as the core mission, with a valid (Let's Encrypt) certificate and an automatic renewal path that restarts the container on success.
- HTTP requests are 301-redirected to HTTPS; `443/tcp` is open in the SG **without** widening any other rule, and SSH stays restricted to `<learner-IP>/32`.
- The Nginx workload runs inside a Docker container named `nginx-web` (`nginx:1.27-alpine`) with `80:80` and `443:443` host mappings; `docker ps` evidence is captured.
- `docker restart nginx-web` recovers `/health` within seconds; reboot of the EC2 instance also brings the container back via `--restart unless-stopped`.
- `06-1/README.md` has a **Bonus Features** section that names the image, shows the run command, lists the port mapping, and embeds **at least two** verification screenshots (subject §5 Bonus 2 explicit requirement).
- `docs/architecture.png` is updated to show EIP + 443 + container; `docs/cleanup-checklist.md` covers EIP, DuckDNS record, certbot timer, container, image, volumes, `/etc/letsencrypt/`.
- All bonus features work on the same instance as the core deployment; no console errors; no broken core flows from `plan.md` §9.
- IAM policy is unchanged from core; no new managed policies, no `AdministratorAccess`, no new IAM principals.
