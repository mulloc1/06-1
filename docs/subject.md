# Cloud Infrastructure & Web Service Deployment Mission

---

## 1. Mission Overview

“I deployed to a server but nothing loads from outside.” Is the port blocked, or is there no security group? The cloud is not just a fast computer—it is **network, security, and IAM** bundled together. You will design an isolated network with a **VPC** and complete a service environment with **least privilege**.

Cloud provides compute, network, and storage to **deploy and operate** services at the scale you need.

In this mission you build **web service infrastructure**: compute, network, storage, and security together. **VPC** isolation, deploy the app on **EC2**, and finish a **externally reachable** web service. Apply **security groups and IAM least privilege**; analyze and fix connectivity and permission issues with **log evidence**.

---

## 2. Final Deliverable

Submit the following **four deliverables**.

### 2.1 Architecture Diagram (One Page)

| Item | Requirement |
|------|-------------|
| **Format** | PNG or PDF |
| **Content** | VPC, Subnet, Internet Gateway, EC2, Security Group, and **external → service** traffic flow |
| **Submit** | One file: `docs/architecture.(png|pdf)` |

### 2.2 External Access Proof

Verify external access with **one** of:

| Method | Verification |
|--------|--------------|
| **(A)** | Browser: `http://<public-ip>` |
| **(B)** | `GET http://<public-ip>/health` |

- **Normal response** (e.g. 200 OK, “OK” or fixed text)
- **Submit**: chosen method (A/B), URL or IP in **README** + at least **one screenshot**

### 2.3 Troubleshooting Report

| Item | Requirement |
|------|-------------|
| **Minimum** | **1+** case — symptom → hypothesis → verification → action → result → prevention |
| **Submit** | One file: `docs/troubleshooting.(md|pdf)` |

### 2.4 Resource Cleanup Checklist

| Item | Requirement |
|------|-------------|
| **Purpose** | Clean up after lab; minimize billing risk |
| **Submit** | One file: `docs/cleanup-checklist.md` |
| **(Optional)** | Billing or resource list screenshot |

---

## 3. Learning Objectives

After completing this assignment, learners should be able to explain the following on their own.

1. Roles of **VPC**, **Subnet**, **Route Table**, **Internet Gateway** and traffic flow.
2. Difference between **Security Group** and **IAM**, and why/how **least privilege** is applied.
3. Settings needed for external requests to reach the EC2 web server (routing, public IP, security group).
4. Troubleshooting with **hypothesis → verification → action** from logs and symptoms.
5. Common **billing** drivers and safe **cleanup order** for lab resources.

---

## 4. Functional Requirements

You must satisfy **all** of the following.

### 4.1 Network

| Item | Requirement |
|------|-------------|
| **VPC** | **1** created |
| **Public Subnet** | **1** |
| **Internet Gateway** | Attached to VPC |
| **Routing** | Public subnet route table: **0.0.0.0/0 → IGW** |
| **Outbound** | Instances in public subnet reach internet (e.g. `curl https://example.com` succeeds) |

### 4.2 Compute & Web Server

| Item | Requirement |
|------|-------------|
| **EC2** | **1** instance in public subnet |
| **SSH** | Can connect to instance |
| **Web server** | Nginx (etc.) installed and running |
| **Local check** | On instance: `curl http://localhost` → **200** |

### 4.3 Access Control (Security Group)

| Item | Requirement |
|------|-------------|
| **Principle** | Inbound: **only required ports** |
| **HTTP (80)** | From **0.0.0.0/0** |
| **SSH (22)** | Only from **learner’s IP** (or specified range) |
| **Forbidden** | **No** rule allowing **all ports (0–65535)** from 0.0.0.0/0 |

### 4.4 IAM Least Privilege

| Item | Requirement |
|------|-------------|
| **Principal** | **1** lab IAM user or role |
| **Scope** | Limited to what EC2/VPC/Security Group lab needs |
| **Forbidden** | **No** **AdministratorAccess** |
| **Example** | Do not grant unrelated S3, RDS, etc. |

### 4.5 External Access (Pick One)

| Method | Requirement |
|--------|-------------|
| **(A)** | Browser `http://<public-ip>` → page OK |
| **(B)** | `GET http://<public-ip>/health` → **200**, fixed body (e.g. “OK”) |

- Document chosen method in **README**

### 4.6 Operations (Avoid Charges)

- Clean up after lab; checklist shows **terminated/deleted** evidence
- At minimum verify: **EC2**, **EBS**, **Elastic IP**, **Internet Gateway**, **VPC**

---

## 5. Bonus (Optional)

### Bonus 1 — HTTPS

Connect a free subdomain (or owned domain) and HTTPS with **Let’s Encrypt**, etc.

### Bonus 2 — Web Service via Docker on EC2

Install **Docker** on EC2 and run the web service in a **container** (your prior mission image or a public image).

| Check | Requirement |
|-------|-------------|
| **Required (internal)** | On instance: `curl http://localhost` (or mapped port) → OK (e.g. 200) |
| **Required (external)** | `http://<public-ip>` or `GET /health` → normal response |

**README** must include:

- Image name and run method
- **Port mapping**
- At least **2** verification screenshots
