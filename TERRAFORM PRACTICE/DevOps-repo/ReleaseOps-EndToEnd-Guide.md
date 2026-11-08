# ReleaseOps — End-to-End CI/CD Project (AWS Free Tier, mapped to Azure)

**Built for this JD:** Azure DevOps CI/CD · IaC · PowerShell/Bash/Python · Git/GitHub · Docker & Kubernetes · Azure Monitor/App Insights

**Why this approach:** You have an AWS Free Tier account and a Windows Server + VS Code setup, but the job wants **Azure DevOps**. The fix: use **real Azure DevOps** (it's cloud-agnostic and free for solo use) to build and deploy **real infrastructure on AWS**, and learn the AWS↔Azure service mapping cold. In the interview you say: *"I built this on AWS free tier for cost reasons, using Azure DevOps for the pipeline — here's exactly how each AWS service maps to what I'd use in a pure-Azure shop."* That's a stronger, more honest story than a toy demo, and it doubles your surface area (you can speak to both clouds).

---

## 1. Architecture at a glance

```
Developer (VS Code, Windows Server)
        │  git push
        ▼
   GitHub Repo (main / develop / feature/* / release/*)
        │  webhook / PR trigger
        ▼
   Azure DevOps Pipelines (CI)
        │  1. lint + unit test (pytest)
        │  2. docker build
        │  3. docker push → Amazon ECR
        ▼
   Azure DevOps Pipelines (CD) — multi-stage, approval gates
        │  Dev (auto-deploy) → Staging (auto + smoke test) → Prod (manual approval)
        ▼
   AWS infra provisioned by Terraform:
     - VPC, Subnet, Security Group          (≈ Azure VNet, Subnet, NSG)
     - EC2 t2.micro/t3.micro (free tier)     (≈ Azure VM B1s)
     - k3s (lightweight Kubernetes) on EC2   (≈ Azure Kubernetes Service, AKS)
     - Amazon ECR                            (≈ Azure Container Registry, ACR)
     - IAM roles/policies                    (≈ Azure RBAC / Managed Identity)
     - AWS Secrets Manager                   (≈ Azure Key Vault)
     - CloudWatch Logs + Alarms + Dashboard  (≈ Azure Monitor / Log Analytics / App Insights)
     - S3 (Terraform remote state)           (≈ Azure Storage Account, blob container)
```

**The app itself:** deliberately simple — a Python Flask "orders" API with a `/health` endpoint and a `/metrics` endpoint, containerized with Docker, deployed as a Kubernetes Deployment + Service on a single-node k3s cluster. Simple app, real pipeline — the pipeline is what the interview cares about.

---

## 2. Why each mandatory skill is covered

| JD requirement | Where it lives in this project |
|---|---|
| Azure DevOps build/release/deployment pipelines | Section 7 — multi-stage YAML pipeline, 3 environments, approval gates |
| CI/CD for multiple environments | Dev/Staging/Prod stages with different variable groups |
| IaC (ARM/Terraform) | Section 5 — full Terraform module set |
| PowerShell/Bash/Python | Bootstrap script in PowerShell (run from Windows Server), deploy script in Bash, app in Python |
| Git/GitHub/Azure Repos | Section 4 — GitFlow-lite branching, PR policies |
| Docker & Kubernetes | Section 3 (Docker) + Section 6 (k3s manifests) |
| Monitoring & logging | Section 8 — CloudWatch + optional Prometheus/Grafana on k3s |

---

## 3. Prerequisites & environment setup (Windows Server + VS Code)

Install on your Windows Server box:

```powershell
# Run in an elevated PowerShell prompt
winget install -e --id Git.Git
winget install -e --id Microsoft.AzureCLI
winget install -e --id Amazon.AWSCLI
winget install -e --id Hashicorp.Terraform
winget install -e --id Docker.DockerDesktop   # or use the EC2 box for docker builds if licensing is an issue
winget install -e --id Kubernetes.kubectl
winget install -e --id Python.Python.3.12
```

VS Code extensions: `Terraform (HashiCorp)`, `Azure Pipelines`, `Docker`, `Python`, `Kubernetes`, `GitLens`.

Accounts you need (all free):
- AWS account (Free Tier — new accounts get 12 months of 750 hrs/month t2.micro/t3.micro EC2, 5 GB S3, 500 MB ECR, CloudWatch basics)
- GitHub account (free)
- Azure DevOps organization at dev.azure.com (free — 5 users, 1 Microsoft-hosted parallel job with 1,800 build minutes/month for private repos, unlimited for public)

Configure CLIs once:

```powershell
aws configure                 # access key, secret key, region (pick ap-south-1 for Bengaluru latency)
az login
```

---

## 4. Version control & branching strategy

```
main         → always deployable, protected, maps to Prod
develop      → integration branch, maps to Staging
feature/*    → short-lived, PR into develop
release/*    → cut from develop, PR into main + tag
hotfix/*     → cut from main, PR back into main and develop
```

In GitHub: branch protection on `main` and `develop` — require PR, 1 approval, passing CI check before merge. This is what you describe when the JD says "implement version control, branching strategies, and release management."

```bash
mkdir releaseops && cd releaseops
git init
git checkout -b main
git checkout -b develop
```

---

## 5. Infrastructure as Code (Terraform → AWS, explained in Azure terms)

Folder layout:

```
infra/
  backend.tf
  providers.tf
  variables.tf
  modules/
    network/
    compute/
    ecr/
    monitoring/
  envs/
    dev/main.tf
    staging/main.tf
    prod/main.tf
```

**`providers.tf`**
```hcl
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = var.aws_region
}
```

**`modules/network/main.tf`** — AWS VPC ≈ Azure Virtual Network
```hcl
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "${var.env}-vpc" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block               = var.subnet_cidr
  map_public_ip_on_launch  = true
  availability_zone        = var.az
  tags = { Name = "${var.env}-public-subnet" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "rta" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.rt.id
}

# Security Group ≈ Azure NSG
resource "aws_security_group" "app_sg" {
  name   = "${var.env}-app-sg"
  vpc_id = aws_vpc.main.id

  ingress { from_port = 22   to_port = 22   protocol = "tcp" cidr_blocks = [var.admin_cidr] }   # SSH — lock to your IP
  ingress { from_port = 6443 to_port = 6443 protocol = "tcp" cidr_blocks = [var.admin_cidr] }   # k3s API
  ingress { from_port = 30080 to_port = 30080 protocol = "tcp" cidr_blocks = ["0.0.0.0/0"] }    # app NodePort
  egress  { from_port = 0    to_port = 0    protocol = "-1"  cidr_blocks = ["0.0.0.0/0"] }
}
```

**`modules/compute/main.tf`** — EC2 ≈ Azure VM, runs k3s
```hcl
resource "aws_instance" "app_node" {
  ami                    = var.ami_id          # Amazon Linux 2023, free-tier eligible
  instance_type          = "t3.micro"          # free tier: 750 hrs/month for 12 months
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.sg_id]
  key_name               = var.key_name
  iam_instance_profile   = aws_iam_instance_profile.app_profile.name

  user_data = file("${path.module}/bootstrap.sh")

  tags = { Name = "${var.env}-app-node" }
}

# IAM role ≈ Azure Managed Identity + RBAC role assignment
resource "aws_iam_role" "app_role" {
  name = "${var.env}-app-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy_attachment" "ecr_pull" {
  role       = aws_iam_role.app_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_instance_profile" "app_profile" {
  name = "${var.env}-app-profile"
  role = aws_iam_role.app_role.name
}
```

**`modules/compute/bootstrap.sh`** — runs on first boot, installs Docker + k3s
```bash
#!/bin/bash
set -euo pipefail
yum update -y
yum install -y docker
systemctl enable docker && systemctl start docker
curl -sfL https://get.k3s.io | sh -
mkdir -p /home/ec2-user/.kube
cp /etc/rancher/k3s/k3s.yaml /home/ec2-user/.kube/config
chown ec2-user:ec2-user /home/ec2-user/.kube/config
```

**`modules/ecr/main.tf`** — Amazon ECR ≈ Azure Container Registry
```hcl
resource "aws_ecr_repository" "app" {
  name                 = "${var.env}-releaseops-app"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration { scan_on_push = true }   # ≈ ACR Microsoft Defender image scan
}

resource "aws_ecr_lifecycle_policy" "expire_untagged" {
  repository = aws_ecr_repository.app.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Expire untagged images after 7 days"
      selection    = { tagStatus = "untagged", countType = "sinceImagePushed", countUnit = "days", countNumber = 7 }
      action       = { type = "expire" }
    }]
  })
}
```

**`modules/monitoring/main.tf`** — CloudWatch ≈ Azure Monitor + Log Analytics
```hcl
resource "aws_cloudwatch_log_group" "app_logs" {
  name              = "/releaseops/${var.env}/app"
  retention_in_days = 14
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.env}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  dimensions          = { InstanceId = var.instance_id }
  alarm_actions       = [var.sns_topic_arn]   # ≈ Azure Monitor Action Group
}
```

**`envs/dev/main.tf`** — wires the modules together per environment; `staging` and `prod` mirror this with different `env` and `instance_type` (prod uses a slightly larger free-tier-adjacent instance if you outgrow the limit — flag the cost tradeoff explicitly in your notes).

Remote state (so state isn't just a local file — talk about this in interviews as a team-collaboration practice):

**`backend.tf`**
```hcl
terraform {
  backend "s3" {
    bucket = "releaseops-tfstate-<your-unique-suffix>"
    key    = "envs/dev/terraform.tfstate"
    region = "ap-south-1"
    encrypt = true
    dynamodb_table = "releaseops-tf-locks"   # state locking ≈ Azure Storage blob lease
  }
}
```

Apply:
```bash
cd infra/envs/dev
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

---

## 6. Containerize the app + deploy to Kubernetes (k3s)

**`app/app.py`**
```python
from flask import Flask, jsonify
import time, os

app = Flask(__name__)
START = time.time()

@app.route("/")
def index():
    return jsonify(service="releaseops-orders-api", env=os.getenv("APP_ENV", "dev"))

@app.route("/health")
def health():
    return jsonify(status="ok"), 200

@app.route("/metrics")
def metrics():
    return jsonify(uptime_seconds=round(time.time() - START, 2))

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
```

**`app/Dockerfile`**
```dockerfile
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
EXPOSE 5000
HEALTHCHECK --interval=30s CMD python -c "import urllib.request as u; u.urlopen('http://localhost:5000/health')" || exit 1
CMD ["python", "app.py"]
```

**`k8s/deployment.yaml`**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: releaseops-app
spec:
  replicas: 2
  selector:
    matchLabels: { app: releaseops-app }
  template:
    metadata:
      labels: { app: releaseops-app }
    spec:
      containers:
        - name: app
          image: <ecr-repo-uri>:${IMAGE_TAG}
          ports: [{ containerPort: 5000 }]
          env: [{ name: APP_ENV, value: "${ENVIRONMENT}" }]
          readinessProbe: { httpGet: { path: /health, port: 5000 }, initialDelaySeconds: 5 }
          resources:
            requests: { cpu: "50m", memory: "64Mi" }
            limits:   { cpu: "200m", memory: "128Mi" }
---
apiVersion: v1
kind: Service
metadata:
  name: releaseops-app-svc
spec:
  type: NodePort
  selector: { app: releaseops-app }
  ports: [{ port: 80, targetPort: 5000, nodePort: 30080 }]
```

This gives you real talking points: **Deployment** (self-healing, replica count), **readiness probes**, **resource requests/limits**, **Service/NodePort** vs Ingress tradeoffs — all standard AKS interview questions too.

---

## 7. Azure DevOps CI/CD pipeline (multi-stage, multi-environment)

Create the Azure DevOps project → New Pipeline → connect your GitHub repo → add a Service Connection of type "Generic" or "AWS" (use an AWS access key with least-privilege ECR + EC2 permissions — this is your chance to talk about **service connections and secret management** in the interview).

**`azure-pipelines.yml`**
```yaml
trigger:
  branches:
    include: [main, develop]

variables:
  imageRepo: releaseops-app
  awsRegion: ap-south-1

stages:
- stage: CI
  jobs:
  - job: BuildAndTest
    pool: { vmImage: 'ubuntu-latest' }
    steps:
      - task: UsePythonVersion@0
        inputs: { versionSpec: '3.12' }
      - script: |
          pip install -r app/requirements.txt
          pip install pytest
          pytest app/tests -v
        displayName: 'Unit tests'
      - task: Docker@2
        inputs:
          command: build
          Dockerfile: app/Dockerfile
          tags: $(Build.BuildId)
      - script: |
          aws ecr get-login-password --region $(awsRegion) | docker login --username AWS --password-stdin $(ECR_REGISTRY)
          docker tag $(imageRepo):$(Build.BuildId) $(ECR_REGISTRY)/$(imageRepo):$(Build.BuildId)
          docker push $(ECR_REGISTRY)/$(imageRepo):$(Build.BuildId)
        displayName: 'Push to ECR'
        env:
          AWS_ACCESS_KEY_ID: $(AWS_ACCESS_KEY_ID)
          AWS_SECRET_ACCESS_KEY: $(AWS_SECRET_ACCESS_KEY)

- stage: DeployDev
  dependsOn: CI
  condition: succeeded()
  jobs:
  - deployment: DeployToDev
    environment: 'dev'
    pool: { vmImage: 'ubuntu-latest' }
    strategy:
      runOnce:
        deploy:
          steps:
            - script: |
                export KUBECONFIG=$(dev.kubeconfig)
                export IMAGE_TAG=$(Build.BuildId)
                export ENVIRONMENT=dev
                envsubst < k8s/deployment.yaml | kubectl apply -f -
              displayName: 'kubectl apply — dev'

- stage: DeployStaging
  dependsOn: DeployDev
  condition: succeeded()
  jobs:
  - deployment: DeployToStaging
    environment: 'staging'          # add an approval check on this Environment in Azure DevOps UI
    pool: { vmImage: 'ubuntu-latest' }
    strategy:
      runOnce:
        deploy:
          steps:
            - script: |
                export KUBECONFIG=$(staging.kubeconfig)
                export IMAGE_TAG=$(Build.BuildId)
                export ENVIRONMENT=staging
                envsubst < k8s/deployment.yaml | kubectl apply -f -
            - script: curl -f http://$(STAGING_IP):30080/health
              displayName: 'Smoke test'

- stage: DeployProd
  dependsOn: DeployStaging
  condition: succeeded()
  jobs:
  - deployment: DeployToProd
    environment: 'prod'             # manual approval gate configured here — required reviewer(s)
    pool: { vmImage: 'ubuntu-latest' }
    strategy:
      runOnce:
        deploy:
          steps:
            - script: |
                export KUBECONFIG=$(prod.kubeconfig)
                export IMAGE_TAG=$(Build.BuildId)
                export ENVIRONMENT=prod
                envsubst < k8s/deployment.yaml | kubectl apply -f -
```

In the Azure DevOps UI: **Pipelines → Environments** — create `dev`, `staging`, `prod`, and on `staging`/`prod` add an **Approvals check** (yourself as approver, simulating a lead sign-off). This is exactly the "release management with approval gates" line from the JD.

Store `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and each environment's kubeconfig as **secret variables** in a Variable Group (Pipelines → Library) — never commit them. Talk about this as your "secrets management" answer even though the underlying vault (AWS Secrets Manager) maps to Azure Key Vault.

---

## 8. Monitoring & logging

- **CloudWatch Agent** on the EC2 node ships syslog + Docker logs to the log group created in Terraform (`modules/monitoring`). ≈ Azure Monitor Agent shipping to a Log Analytics workspace.
- **CloudWatch Alarm** on CPU > 80% notifying an SNS topic (email) ≈ Azure Monitor **metric alert** + **Action Group**.
- Optional stretch (reuses skills from your ObserveOps project): install `kube-prometheus-stack` via Helm on the k3s node for Grafana dashboards — gives you a second, K8s-native monitoring story to contrast against the CloudWatch/Azure Monitor one.
- **Application-level logging**: have Flask log structured JSON to stdout; k3s captures container stdout/stderr — this is the same pattern App Insights uses for App Service/AKS logs, so the explanation transfers directly.

---

## 9. Security & compliance checklist (talk-track for "ensure compliance with security policies")

- IAM role attached to EC2 is scoped to `AmazonEC2ContainerRegistryReadOnly` only — least privilege (≈ Azure Managed Identity with a scoped custom role, not Owner/Contributor).
- Security Group only opens 22 (from your IP), 6443 (k3s API, from your IP), and 30080 (app) — nothing else (≈ NSG rules).
- Secrets never in Git — Variable Groups in Azure DevOps + AWS Secrets Manager for anything the app itself needs at runtime (≈ Key Vault referenced via Managed Identity).
- Branch protection + required PR review on `main`/`develop` (≈ Azure Repos branch policies).
- ECR image scanning on push (≈ ACR + Defender for Containers).
- Terraform state encrypted at rest in S3 + locked via DynamoDB (≈ Storage Account with soft delete + blob lease locking).

---

## 10. Roles — who does what (for the "collaborate with dev/QA" line)

| Role | Responsibility in this project |
|---|---|
| **You (DevOps/Cloud/SRE)** | Own the pipeline, IaC, environment promotion strategy, monitoring/alerting, incident response, cost guardrails, security baseline |
| **Developer** | Owns `app/` code, writes unit tests, raises PRs into `develop`, fixes failures the CI stage surfaces |
| **QA/Test Engineer** | Owns smoke/integration tests run in the Staging stage, signs off before Prod approval |
| **Release/Product owner** | Approves the Prod deployment gate, decides release timing/rollback |
| **Security/Compliance** | Reviews IAM policies, NSG/SG rules, and secret handling periodically; in a real org, gates merges with a security scan stage |

In an interview, frame your role as the **connective tissue**: you don't write the app's business logic and you don't approve the release business decision — you make sure the path from a developer's `git push` to a running, observable, rollback-able production service is fast, safe, and repeatable.

---

## 11. Cost — staying at $0

| Resource | Free tier limit | Risk |
|---|---|---|
| EC2 t3.micro | 750 hrs/month, 12 months | Fine for 1 always-on instance; **do not** run dev+staging+prod as 3 separate EC2s simultaneously — you'll exceed 750 hrs. Use one node with 3 k3s namespaces (dev/staging/prod) instead, or stop instances when not actively demoing |
| EBS storage | 30 GB/month | Default 8GB root volume is well under this |
| S3 (Terraform state) | 5 GB | Trivial for state files |
| ECR | 500 MB/month | Each image ~150-200MB; the lifecycle policy above auto-expires untagged images to stay under this |
| CloudWatch Logs | 5 GB ingestion, 5 GB storage | Fine at this scale; watch log retention (set to 14 days, not "Never expire") |
| Data transfer out | 100 GB/month | Won't come close for a portfolio demo |
| Azure DevOps | 5 users, 1 Microsoft-hosted parallel job, 1,800 min/month | Plenty for solo CI/CD |

**Practical approach:** run one EC2 node with k3s namespaces `dev`/`staging`/`prod` instead of three EC2 instances — it's cheaper, and it's also a legitimate real-world pattern (namespace isolation) you can defend in an interview. `terraform destroy` everything when you're not actively practicing to guarantee $0.

---

## 12. Suggested timeline (3 weeks, evenings/weekends pace)

- **Days 1–3:** App + Docker + Git repo + branching strategy set up and pushed to GitHub
- **Days 4–8:** Terraform modules written and applied (network → compute → ecr → monitoring), k3s verified working on EC2, app deployed manually via `kubectl apply` once to confirm the manifests are correct
- **Days 9–14:** Azure DevOps project + pipeline YAML, service connection, variable groups, environments with approval gates — get the full CI→Dev→Staging→Prod flow green
- **Days 15–18:** Monitoring/alerting wired up, security checklist applied, README + architecture diagram written
- **Days 19–21:** Interview prep — rehearse the architecture walkthrough, the AWS→Azure mapping table, and 2-3 STAR stories (e.g., a deliberately-broken deploy you diagnosed and fixed)

---

## 13. Full AWS ↔ Azure service mapping (your interview cheat sheet)

| AWS (what you built) | Azure (what you'd say in interview) |
|---|---|
| VPC | Virtual Network (VNet) |
| Subnet | Subnet |
| Security Group | Network Security Group (NSG) |
| Internet Gateway | Internet-facing Load Balancer / Public IP |
| EC2 | Virtual Machine |
| IAM Role/Policy | Managed Identity + RBAC Role Assignment |
| ECR | Azure Container Registry (ACR) |
| k3s (self-managed K8s) | Azure Kubernetes Service (AKS, managed) |
| S3 | Storage Account (Blob Container) |
| DynamoDB (state lock) | Storage Account blob lease (state locking) |
| Secrets Manager | Key Vault |
| CloudWatch Logs | Log Analytics Workspace |
| CloudWatch Alarms + SNS | Azure Monitor Alerts + Action Groups |
| CloudWatch Dashboard | Azure Monitor Workbook / Dashboard |
| Terraform | Terraform (same tool) or ARM/Bicep |
| GitHub | GitHub or Azure Repos |
| Azure DevOps Pipelines | (same — used natively here) |

---

## 14. What to say when asked "is this AWS or Azure experience?"

Be direct and confident, don't over-explain: *"I have hands-on Azure DevOps pipeline experience — that part is identical to what you'd use in a pure-Azure environment. The infrastructure underneath is AWS because that's the free tier I had access to, so I built it with an explicit AWS-to-Azure mapping in mind: everywhere I used an IAM role, in Azure that's a Managed Identity; everywhere I used ECR, that's ACR; my EC2+k3s setup mirrors what AKS gives you managed. I'm confident I could translate this pipeline to ARM/Bicep and AKS within days, not weeks."* This is honest and shows you understand *why* services exist, not just their names — which is what's actually being tested.

---

## 15. Teardown (run this after every practice session to guarantee $0 spend)

```bash
cd infra/envs/dev && terraform destroy -auto-approve
cd ../staging && terraform destroy -auto-approve
cd ../prod && terraform destroy -auto-approve
```

Also manually check: AWS Console → EC2 (no running instances), ECR (repos can stay, they're free under 500MB), S3 (state bucket can stay, it's tiny), CloudWatch (log groups can stay, they're free under 5GB).
