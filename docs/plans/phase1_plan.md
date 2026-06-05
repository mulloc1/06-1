# Phase 1 — Network (VPC + Subnet + IGW + Route Table)

> Parent plan: [`docs/plan.md`](../plan.md) §6 Phase 1
> Subject reference: [`docs/subject.md`](../subject.md) §4.1

This phase provisions the **network foundation** that the EC2 instance will land on in Phase 2: one VPC, one public subnet in a single AZ, one Internet Gateway, and one public route table with a default route to the IGW. No compute or security group rules yet — those come next. Following `.cursorrules` §4 (Minimal-First / YAGNI), a second AZ, private subnets, and NAT Gateway are explicitly out of scope.

---

## 1. Goal

- Create the minimum AWS network listed in `plan.md` §4.1: one VPC `10.0.0.0/16`, one public subnet `10.0.1.0/24` in `ap-northeast-2a`, one IGW attached to the VPC, one public route table with `0.0.0.0/0 → IGW` associated to the subnet.
- Enable `MapPublicIpOnLaunch = true` on the public subnet so EC2 instances auto-receive a public IPv4 in Phase 2 (no Elastic IP in core scope per `plan.md` §2 decisions table).
- Result: an empty but **routable** public subnet — any EC2 launched into it with an open SG will have a path to the internet in both directions.

---

## 2. Scope (In / Out)

**In scope**
- Create one VPC with CIDR `10.0.0.0/16`, name tag `lab-cloud-web-vpc`, DNS hostnames enabled.
- Create one subnet `10.0.1.0/24` in `ap-northeast-2a`, name tag `lab-cloud-web-public-subnet`.
- Enable auto-assign public IPv4 on the subnet.
- Create one Internet Gateway, name tag `lab-cloud-web-igw`, attach it to the VPC.
- Create one route table, name tag `lab-cloud-web-public-rt`, add route `0.0.0.0/0 → lab-cloud-web-igw`, associate it with the public subnet.
- Capture screenshot evidence of (a) the route table routes view and (b) the subnet's "Auto-assign public IPv4" being **enabled**, into `docs/evidence/` for the troubleshooting/diagram references.

**Out of scope**
- Security groups (Phase 2 launches the EC2 with `lab-web-sg`).
- EC2 instance, key pair, AMI selection (Phase 2).
- Second AZ, private subnet, NAT Gateway, VPC peering, endpoints (all `.cursorrules` §4 YAGNI).
- DHCP option sets, Network ACL changes (default NACL is fine — SG handles policy).

---

## 3. Tasks

### 3.1 Pre-flight (region pin)
- AWS console region selector → **Asia Pacific (Seoul) `ap-northeast-2`**. Verify the URL contains `region=ap-northeast-2`.
- CLI sanity check: `aws ec2 describe-availability-zones --profile lab --region ap-northeast-2 --query 'AvailabilityZones[].ZoneName'` should include `ap-northeast-2a`.

### 3.2 VPC
- VPC console → Your VPCs → Create VPC.
  - **Resources to create**: VPC only (do **not** use "VPC and more" — it provisions subnets/NAT/IGW for you and can blow past the minimal scope).
  - Name tag: `lab-cloud-web-vpc`.
  - IPv4 CIDR: `10.0.0.0/16`.
  - IPv6 CIDR: none.
  - Tenancy: default.
- After creation: select the VPC → Actions → **Edit VPC settings** → enable **DNS hostnames** (DNS resolution is on by default). This makes `ec2-…compute.amazonaws.com` hostnames work for the instance.

### 3.3 Internet Gateway
- VPC console → Internet gateways → Create internet gateway.
  - Name tag: `lab-cloud-web-igw`.
- Select the new IGW → **Actions → Attach to VPC** → choose `lab-cloud-web-vpc`. Confirm state becomes `Attached`.

### 3.4 Public Subnet
- VPC console → Subnets → Create subnet.
  - VPC: `lab-cloud-web-vpc`.
  - Subnet name: `lab-cloud-web-public-subnet`.
  - Availability Zone: `ap-northeast-2a`.
  - IPv4 CIDR block: `10.0.1.0/24`.
- After creation: select the subnet → **Actions → Edit subnet settings** → enable **Enable auto-assign public IPv4 address**. Save.

### 3.5 Public Route Table
- VPC console → Route tables → Create route table.
  - Name tag: `lab-cloud-web-public-rt`.
  - VPC: `lab-cloud-web-vpc`.
- Open the new route table → Routes → **Edit routes**:
  - Existing: `10.0.0.0/16 → local` (auto-added, do **not** delete).
  - Add: `Destination 0.0.0.0/0 → Target Internet Gateway → lab-cloud-web-igw`.
  - Save.
- Subnet associations tab → **Edit subnet associations** → check `lab-cloud-web-public-subnet` → Save. The subnet's implicit association with the main route table is replaced by this explicit one.

### 3.6 Evidence capture
- Route tables → `lab-cloud-web-public-rt` → Routes tab. Screenshot showing both `local` and `0.0.0.0/0 → IGW` routes. Save as `docs/evidence/05a-route-table.png` (numbering reserves `05` family for SG-and-network screenshots referenced by the troubleshooting report).
- Subnets → `lab-cloud-web-public-subnet` → Details tab. Screenshot showing **Auto-assign public IPv4 address: Yes**. Save as `docs/evidence/05b-subnet-autoassign.png`.

---

## 4. Files Touched

| File / Resource | Action |
| ---- | ------ |
| AWS VPC `lab-cloud-web-vpc` (`10.0.0.0/16`) | create |
| AWS IGW `lab-cloud-web-igw` | create + attach to VPC |
| AWS Subnet `lab-cloud-web-public-subnet` (`10.0.1.0/24` in `ap-northeast-2a`) | create + enable auto-assign public IPv4 |
| AWS Route Table `lab-cloud-web-public-rt` | create + add `0.0.0.0/0 → IGW` + associate subnet |
| `06-1/docs/evidence/05a-route-table.png` | create (route table routes screenshot) |
| `06-1/docs/evidence/05b-subnet-autoassign.png` | create (subnet auto-assign screenshot) |

---

## 5. Acceptance Criteria

- [ ] `aws ec2 describe-vpcs --profile lab --region ap-northeast-2 --filters Name=tag:Name,Values=lab-cloud-web-vpc --query 'Vpcs[0].CidrBlock'` returns `10.0.0.0/16`.
- [ ] `aws ec2 describe-internet-gateways --profile lab --region ap-northeast-2 --filters Name=tag:Name,Values=lab-cloud-web-igw --query 'InternetGateways[0].Attachments[0].State'` returns `available` and is attached to `lab-cloud-web-vpc`.
- [ ] `aws ec2 describe-subnets --profile lab --region ap-northeast-2 --filters Name=tag:Name,Values=lab-cloud-web-public-subnet --query 'Subnets[0].MapPublicIpOnLaunch'` returns `true`; `CidrBlock` is `10.0.1.0/24`; `AvailabilityZone` is `ap-northeast-2a`.
- [ ] The public route table has **exactly two** routes: `10.0.0.0/16 → local` and `0.0.0.0/0 → igw-…` (the IGW just created). No other `0.0.0.0/0` target.
- [ ] The subnet's **explicit** association is the `lab-cloud-web-public-rt` (not the main route table).
- [ ] Both evidence screenshots exist under `docs/evidence/` with the locked filenames.
- [ ] No security group rules were touched in this phase (default SG remains the AWS default).

---

## 6. Commit

```
docs: record vpc, subnet, igw, and route table provisioning
```

One commit covers both evidence screenshots and any README cross-link added later. Per `.cursorrules` §6 (Logical Commit Unit), the network is a single logical unit — committing IGW separately from its route would leave the repo in a half-described state.

---

## 7. Risks / Notes

- **Region drift**: if the console silently flips to `us-east-1` mid-task, resources land in the wrong region and Phase 6 cleanup will miss them. Pin region first, verify region in the URL on every page.
- The "VPC and more" wizard tempts a one-click setup but creates extra subnets and (depending on options) a NAT Gateway. NAT Gateway has an hourly charge with no learning value here — do **not** use it.
- If `MapPublicIpOnLaunch` is left as `false`, Phase 2's EC2 will boot without a public IP and Phase 3 will fail at external access. The negative symptom is "instance running, SG correct, can't reach from internet" — call out this case in `troubleshooting.md` if it actually happens.
- Default NACL is stateless and allows all in/out by default; do **not** lock it down — the lab uses **Security Groups** for policy (subject §4.3). If a custom NACL was created earlier, ensure it allows ephemeral inbound (32768–65535) for response traffic.
- VPC, IGW, Subnet, and Route Table are all **free**. The only chargeable item in this phase is the public IPv4 once it gets assigned to an instance in Phase 2 (post-Feb-2024 pricing).

---

## 8. Definition of Done

- The four network components from `plan.md` §4.1 exist with the exact CIDRs, tags, and AZ locked in §2 decisions.
- Auto-assign public IPv4 is enabled on the subnet so Phase 2 doesn't need an Elastic IP.
- Evidence screenshots are in place for the troubleshooting report and architecture diagram to reference.
- Any EC2 launched into `lab-cloud-web-public-subnet` with an open SG can reach the internet — verified for real in Phase 2.
