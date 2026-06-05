# Phase 4 — Architecture Diagram

> Parent plan: [`docs/plan.md`](../plan.md) §6 Phase 4
> Subject reference: [`docs/subject.md`](../subject.md) §2.1

This phase produces the **one-page architecture diagram** required by subject §2.1: a single PNG exported from draw.io that shows VPC, Subnet, Internet Gateway, EC2, Security Group, and the external→service traffic flow. It is the most "design"-shaped deliverable in the assignment and intentionally separated from infrastructure work so the diagram reflects what was **actually built** in Phases 1–3, not what was planned.

---

## 1. Goal

- Author `architecture.drawio` locally with the components from `plan.md` §4.1 and the traffic flow from `plan.md` §4.2.
- Export to `06-1/docs/architecture.png` at a resolution legible on a GitHub README (recommend 1600×900 or similar 16:9).
- Embed the diagram in `06-1/README.md` under the "Architecture" section as a relative path.

---

## 2. Scope (In / Out)

**In scope**
- One layered diagram from "Internet" at the top down to "EC2 (Nginx)", showing in order: Internet, Internet Gateway, Route Table, Public Subnet boundary (CIDR labeled), EC2 instance icon, Security Group boundary around the ENI, and arrow callouts for inbound HTTP/SSH + outbound HTTPS.
- Labels: VPC CIDR (`10.0.0.0/16`), Subnet CIDR (`10.0.1.0/24` / `ap-northeast-2a`), SG name (`lab-web-sg`), instance type (`t3.micro`, AL2023), Nginx, `/health` route.
- One source file (`architecture.drawio`) kept **locally** (not committed — diagram tooling drift is a risk per `plan.md` §8) and one committed PNG export.
- One reference in `README.md` Architecture section: image embed + 1-paragraph caption pointing at the §4.1/§4.2 plan text.

**Out of scope**
- Multiple diagrams (per-component, sequence, etc.) — subject §2.1 says **one** page.
- IAM diagram. IAM is described in text in `README.md` (and the policy JSON in `docs/evidence/06-iam-policy.json`); a graphical IAM panel is YAGNI.
- Animated SVGs, Mermaid diagrams, ASCII art replacements — subject §2.1 requires PNG or PDF.
- HTTPS / Docker / Elastic IP — those are bonus and live in `bonus_plan.md` with their own diagram if needed.

---

## 3. Tasks

### 3.1 Choose tooling
- Use **draw.io / diagrams.net** (`plan.md` §2 decisions table).
- Open https://app.diagrams.net/, create a new diagram, save the source as `architecture.drawio` on the learner's local disk (outside the repo).

### 3.2 Lay out components
Stack the following top-to-bottom, with the AWS shapes from draw.io's "AWS" shape library:

| Layer | Element | Label / Detail |
| --- | --- | --- |
| 0 | Cloud icon "Internet" | client browser / `curl` user |
| 1 | Internet Gateway | `lab-cloud-web-igw` |
| 2 | Route Table | `lab-cloud-web-public-rt` · routes: `0.0.0.0/0 → IGW`, `10.0.0.0/16 → local` |
| 3 | VPC boundary | `lab-cloud-web-vpc` `10.0.0.0/16`, region `ap-northeast-2` |
| 3a | Public Subnet boundary (nested in VPC) | `lab-cloud-web-public-subnet` `10.0.1.0/24` · AZ `ap-northeast-2a` |
| 3a-i | EC2 instance icon (nested in subnet) | `lab-cloud-web-ec2` · `t3.micro` · AL2023 · Nginx |
| 3a-ii | Security Group boundary around the ENI | `lab-web-sg` · inbound `80/0.0.0.0`, `22/<learner-IP>` · outbound `all/0.0.0.0` |

### 3.3 Add arrows / traffic flow
- **Inbound HTTP**: Internet → IGW → Route Table → Subnet → SG (port 80) → EC2 / Nginx. Label the arrow `GET /health → 200 OK`.
- **Inbound SSH**: Same path, terminated at SG (port 22) from `<learner-IP>/32`. Label the arrow `ssh ec2-user@…`.
- **Outbound HTTPS**: EC2 → SG egress → Route Table (`0.0.0.0/0`) → IGW → Internet (`example.com`). Label `dnf install · curl https://example.com`.

Use distinct arrow colors for inbound vs. outbound so the diagram reads at a glance.

### 3.4 Annotate "explicitly not present"
Add a single small footer text frame listing what is **intentionally absent**, since subject §4.6 and `plan.md` §4.1 both note minimal scope:

```
Not in core scope: second AZ, private subnet, NAT Gateway, Elastic IP, HTTPS, IAM instance profile.
(HTTPS + Docker → docs/bonus_plan.md)
```

This pre-empts grader questions and is cheap to add.

### 3.5 Export PNG
- draw.io → File → Export as → PNG.
  - Zoom: 100%; Border width: 10; Transparent background: **off** (white background renders better on dark-mode GitHub).
  - Selection only: **off** (export entire diagram).
- Save as `06-1/docs/architecture.png`.
- Inspect at native size: every label should be legible without zooming.

### 3.6 Embed in README
- Edit `06-1/README.md` Architecture section:

  ```markdown
  ## Architecture

  ![One-page architecture: VPC → IGW → Public Subnet → EC2/Nginx with lab-web-sg](docs/architecture.png)

  Traffic flow and component roles are described in [`docs/plan.md`](docs/plan.md#41-network-topology-subject-41) §4.1–§4.2. The diagram reflects the resources actually built in Phases 1–2 and verified in Phase 3.
  ```

---

## 4. Files Touched

| File | Action |
| ---- | ------ |
| `06-1/docs/architecture.png` | create (one-page diagram) |
| `06-1/README.md` | edit (Architecture section: image embed + caption) |
| `architecture.drawio` (local, NOT committed) | create (source for future edits) |

---

## 5. Acceptance Criteria

- [ ] `06-1/docs/architecture.png` exists, opens, and is legible at native size.
- [ ] The diagram contains **every** element from `plan.md` §4.1: VPC, Public Subnet, IGW, Route Table, EC2, Security Group, and the **external→service** flow arrow.
- [ ] CIDR labels match `plan.md` §2 decisions: VPC `10.0.0.0/16`, Subnet `10.0.1.0/24`, AZ `ap-northeast-2a`, instance type `t3.micro`.
- [ ] At least one arrow is labeled `GET /health → 200 OK` (ties the diagram back to the Phase 3 verification method).
- [ ] At least one arrow shows the **outbound** path `EC2 → IGW → internet` so subject §4.1 outbound requirement is visible in the diagram, not just the text.
- [ ] `06-1/README.md` Architecture section embeds the PNG via relative path `docs/architecture.png` (renders inline on github.com).
- [ ] `architecture.drawio` source is **not** committed (kept locally per `plan.md` §8 risk note on diagram tooling drift).
- [ ] No new AWS resources were created or modified in this phase.

---

## 6. Commit

```
docs: add one-page architecture diagram
```

One commit per `.cursorrules` §6 (Logical Commit Unit). Bundles the PNG and the README edit; they're meaningless apart.

---

## 7. Risks / Notes

- **Drift risk**: if the diagram is edited later but `architecture.drawio` was only kept locally, the next learner cannot reproduce changes. Mitigation: if changes become frequent (unlikely in a one-shot lab), commit the `.drawio` source too.
- **Resolution**: a too-small PNG looks fine in the draw.io preview but illegible on GitHub. Always inspect on github.com after the commit lands (or open the file in Preview at 100%).
- **Don't draw what wasn't built**: if Phase 2 ended up using user-data or an Elastic IP for any reason, the diagram must match the actual setup, not the plan text. Update `plan.md` §2 decisions in the same commit if so.
- **Subject says PNG or PDF**: stick with PNG so it renders inline in README. PDF would require a separate link click, which makes grading slower.
- Diagram tooling is **not** a deliverable. Don't sink hours into pretty AWS icon kits — a clean layered diagram with labels passes grading.

---

## 8. Definition of Done

- The single one-page diagram exists at `docs/architecture.png` and is embedded in `README.md`.
- A reviewer can match every box and arrow in the diagram to a section in `plan.md` §4.
- The diagram closes subject §2.1 deliverable; combined with Phase 3 it closes §2.1 + §2.2.
