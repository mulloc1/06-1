# Phase 2 — EC2 + Nginx + Local Check

> Parent plan: [`docs/plan.md`](../plan.md) §6 Phase 2
> Subject reference: [`docs/subject.md`](../subject.md) §4.2, §4.3, §4.5

This phase launches the **single EC2 instance** that will serve the public web traffic, attaches the **least-privilege security group** `lab-web-sg`, installs Nginx with a `/health` endpoint, and verifies both **on-instance HTTP 200** and **outbound HTTPS 200**. External access from the internet is verified in Phase 3, not here.

---

## 1. Goal

- Launch one `t3.micro` Amazon Linux 2023 instance into the public subnet from Phase 1, with auto-assigned public IPv4 and an ED25519 SSH key pair (`plan.md` §2 decisions).
- Create the security group `lab-web-sg` with inbound `tcp/80` from `0.0.0.0/0` and `tcp/22` from `<learner-IP>/32` only; outbound `all/all` (`plan.md` §4.4).
- Install Nginx, drop the `/health` `location` block, enable + start the service.
- Verify on the instance: `curl -i http://localhost` → `200`, `curl -sI https://example.com` → `200`.
- Capture evidence for `docs/evidence/03-ssh-localhost.png` and `04-outbound-curl.png`.

---

## 2. Scope (In / Out)

**In scope**
- ED25519 key pair `lab-cloud-web-key` created via EC2 console; private key (`lab-cloud-web-key.pem`) downloaded once and stored **outside** the repo at `chmod 400`.
- Security Group `lab-web-sg` in `lab-cloud-web-vpc` with the three rules locked in `plan.md` §4.4.
- EC2 instance `lab-cloud-web-ec2`, `t3.micro`, Amazon Linux 2023 (latest x86_64 AMI), default 8 GiB gp3 root volume, **DeleteOnTermination = true**, in `lab-cloud-web-public-subnet`, **no** Elastic IP, **no** IAM instance profile (subject §4.4 forbids unrelated permissions; the lab user's CLI is the one with AWS API access).
- Nginx installation via `dnf` and a single `/health` `location` block.
- Local verification only (HTTP `localhost` + outbound HTTPS to `example.com`).

**Out of scope**
- External verification from the learner's laptop (Phase 3).
- Browser screenshot of the root page (Phase 3 — needs the public IP).
- Custom AMI, user-data automation, CloudWatch agent (`.cursorrules` §4 YAGNI — manual SSH install gives visible logs the troubleshooting report can quote).
- IAM instance profile, S3 buckets, RDS — out of scope per subject §4.4.

---

## 3. Tasks

### 3.1 Capture learner IP
- On the learner's laptop: `curl -4 https://checkip.amazonaws.com`. Record the result (e.g. `203.0.113.42`). This is the **only** IP allowed for SSH in step 3.3.
- If the laptop is behind a corporate VPN that rotates IPs, prefer the home/office static IP; the SG can be updated later via console.

### 3.2 SSH key pair
- EC2 console → Key Pairs → Create key pair.
  - Name: `lab-cloud-web-key`.
  - Key pair type: **ED25519**.
  - Private key file format: `.pem` (OpenSSH).
- Download `lab-cloud-web-key.pem` **once**; AWS will not show it again.
- On the learner laptop: `mv ~/Downloads/lab-cloud-web-key.pem ~/.ssh/lab-cloud-web-key.pem && chmod 400 ~/.ssh/lab-cloud-web-key.pem`.

### 3.3 Security Group `lab-web-sg`
- EC2 console → Security Groups → Create security group.
  - Name: `lab-web-sg`.
  - Description: `Least-privilege SG for 06-1 lab Nginx instance.`
  - VPC: `lab-cloud-web-vpc`.
- Inbound rules:
  | Type | Protocol | Port | Source | Description |
  | --- | --- | --- | --- | --- |
  | HTTP | TCP | 80 | `0.0.0.0/0` | Public web (subject §4.3) |
  | SSH | TCP | 22 | `<learner-IP>/32` | Operator only |
- Outbound rules: keep the default `All traffic → 0.0.0.0/0` (subject §4.3 says inbound restrictions; outbound is needed for `dnf` + `curl https://example.com`).
- Capture screenshot of the inbound rules → `docs/evidence/05-sg-inbound.png`.

### 3.4 Launch EC2
- EC2 console → Instances → Launch instances.
  - Name: `lab-cloud-web-ec2`.
  - AMI: **Amazon Linux 2023**, latest x86_64.
  - Instance type: `t3.micro`.
  - Key pair: `lab-cloud-web-key`.
  - **Network settings → Edit**:
    - VPC: `lab-cloud-web-vpc`.
    - Subnet: `lab-cloud-web-public-subnet`.
    - Auto-assign public IP: **Enable** (should inherit from subnet; reconfirm).
    - Firewall (security groups): **Select existing** → `lab-web-sg`.
  - Storage: 1 × 8 GiB, gp3, **Delete on termination: Yes** (default).
  - Advanced details: IAM instance profile **none**; user data **empty** (we install Nginx by hand for visible logs).
- Launch. Wait for instance state `running` and status checks `2/2`.

### 3.5 SSH in & install Nginx
- From learner laptop: `ssh -i ~/.ssh/lab-cloud-web-key.pem ec2-user@<public-ip>`. Accept the host fingerprint on first connect.
- On the instance:
  ```bash
  sudo dnf update -y
  sudo dnf install -y nginx
  sudo systemctl enable --now nginx
  systemctl is-active nginx   # → active
  ```

### 3.6 `/health` location block
- Create a drop-in conf so the default `nginx.conf` stays untouched:
  ```bash
  sudo tee /etc/nginx/conf.d/health.conf >/dev/null <<'EOF'
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
  EOF
  sudo nginx -t
  sudo systemctl reload nginx
  ```
- If `nginx -t` complains about a duplicate `default_server`, remove the upstream default server block in `/etc/nginx/nginx.conf` (Amazon Linux 2023 ships one) and reload.

### 3.7 Customize the root page (so Phase 3 browser screenshot proves this instance)
- Edit `/usr/share/nginx/html/index.html` with `sudo` and replace the body with a one-liner like `<h1>06-1 cloud lab — lab-cloud-web-ec2</h1>` so Method (A) screenshots in Phase 3 are visibly this instance, not the distro default.

### 3.8 Local verification
- On the instance:
  ```bash
  curl -i http://localhost           # → HTTP/1.1 200 OK
  curl -i http://localhost/health    # → HTTP/1.1 200 OK + body "OK"
  curl -sI https://example.com       # → HTTP/2 200
  ```
- Capture a terminal screenshot showing the three commands and their outputs → `docs/evidence/03-ssh-localhost.png` (the `localhost` HTTP checks) and `docs/evidence/04-outbound-curl.png` (the `example.com` HTTPS check). Split into two if a single terminal frame won't fit cleanly.

---

## 4. Files Touched

| File / Resource | Action |
| ---- | ------ |
| AWS Key Pair `lab-cloud-web-key` (ED25519) | create |
| AWS Security Group `lab-web-sg` (inbound 80/0.0.0.0, 22/learner-IP) | create |
| AWS EC2 instance `lab-cloud-web-ec2` (t3.micro, AL2023, public subnet) | launch |
| On-instance `/etc/nginx/conf.d/health.conf` | create |
| On-instance `/usr/share/nginx/html/index.html` | edit (one-line custom heading) |
| `06-1/docs/evidence/03-ssh-localhost.png` | create |
| `06-1/docs/evidence/04-outbound-curl.png` | create |
| `06-1/docs/evidence/05-sg-inbound.png` | create |

---

## 5. Acceptance Criteria

- [ ] `aws ec2 describe-instances --profile lab --region ap-northeast-2 --filters Name=tag:Name,Values=lab-cloud-web-ec2 --query 'Reservations[0].Instances[0].[State.Name,InstanceType,PublicIpAddress,SubnetId]'` returns `["running","t3.micro","<public-ip>","<subnet-id of lab-cloud-web-public-subnet>"]`.
- [ ] `aws ec2 describe-security-groups --profile lab --region ap-northeast-2 --filters Name=group-name,Values=lab-web-sg` shows **only** the two inbound rules (80 from `0.0.0.0/0`, 22 from `<learner-IP>/32`). No `0–65535` rule.
- [ ] SSH succeeds: `ssh -i ~/.ssh/lab-cloud-web-key.pem ec2-user@<public-ip>` lands on the shell prompt.
- [ ] On instance: `systemctl is-active nginx` → `active`; `curl -i http://localhost` → `200 OK`; `curl -i http://localhost/health` → `200 OK` + body `OK`.
- [ ] On instance: `curl -sI https://example.com` → `HTTP/2 200` (proves outbound through IGW per Phase 1).
- [ ] From a **non-learner** IP (e.g. mobile hotspot), `ssh -i lab.pem ec2-user@<public-ip>` times out (proves the SG SSH rule is not `0.0.0.0/0`).
- [ ] All three evidence screenshots exist under `docs/evidence/` with the locked filenames.
- [ ] The instance has **no** IAM instance profile attached.

---

## 6. Commit

```
docs: launch ec2, install nginx, and verify local and outbound
```

One commit per `.cursorrules` §6 (Logical Commit Unit). The commit includes the three screenshots and any cross-link added to `README.md`; the on-instance config (`health.conf`, customized `index.html`) is recreated from this plan, not stored in the repo (`plan.md` §3 — no application source code in the core mission).

---

## 7. Risks / Notes

- **Public IP rotates if the instance is stopped/started** — once Phase 3 screenshots are captured against `<public-ip>`, do not stop the instance until Phase 6 teardown. If a stop happens, re-capture Phase 3 evidence with the new IP.
- `nginx -t` failing on `duplicate default_server` is the most common Phase 2 trip — fix by removing the upstream default in `nginx.conf`, not by deleting `health.conf`. Promote this to `troubleshooting.md` if encountered.
- If `curl -sI https://example.com` fails on the instance: check (a) route table has `0.0.0.0/0 → IGW`, (b) subnet is associated with that route table, (c) SG outbound is `all/all`, in that order.
- If external (laptop) `curl http://<public-ip>/health` fails in Phase 3 even though local 200 works here: the most likely cause is the SG inbound HTTP rule (typo on port 80, source not `0.0.0.0/0`) or the subnet's auto-assign public IPv4 silently being `false`.
- **Never** commit `lab-cloud-web-key.pem`; the file lives only at `~/.ssh/lab-cloud-web-key.pem` on the learner laptop. Verify `git status` does not show it.
- Avoid `userdata` for the Nginx install: failures there are silent until SSH-in, and the troubleshooting report benefits from human-visible `dnf` output.

---

## 8. Definition of Done

- The instance is reachable via SSH from the learner IP, runs Nginx, and responds `200` locally on `/` and `/health`.
- The instance can talk outbound to the internet (HTTPS).
- The security group is locked to exactly the two inbound rules in `plan.md` §4.4, with screenshot evidence.
- All three Phase 2 evidence screenshots are committed under `docs/evidence/`.
- The lab is ready for Phase 3 to verify **external** access.
