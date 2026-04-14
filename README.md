# deployServices

**Production-grade microservices deployment project** built for hands-on practice with containerization, orchestration, observability, and CI/CD. Three independent stateless microservices — each in a different framework — ship with a full Docker Compose stack, Kubernetes manifests, Helm charts, Terraform IaC, GitHub Actions pipelines, and an end-to-end observability layer (traces, metrics, logs).

> **Tested and validated on Windows 10/11 + Docker Desktop + Kind and on GitHub Actions (Ubuntu runners). Works on macOS with minimal adjustments ([see macOS note](#macos-note)).**

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Tech Stack](#tech-stack)
- [Why Each Technology](#why-each-technology)
- [Project Structure](#project-structure)
- [Prerequisites (Windows)](#prerequisites-windows)
- [Getting Started — Local (Windows)](#getting-started--local-windows)
  - [Option A: Docker Compose](#option-a-docker-compose)
  - [Option B: Kubernetes via Kind](#option-b-kubernetes-via-kind)
  - [Option C: Terraform](#option-c-terraform)
- [Running Tests](#running-tests)
- [CI/CD — GitHub Actions](#cicd--github-actions)
  - [CI Pipeline](#ci-pipeline-ciyml)
  - [CD Pipeline](#cd-pipeline-deployyml)
  - [Setting Up CI/CD for Your Fork](#setting-up-cicd-for-your-fork)
- [Service API Reference](#service-api-reference)
- [Observability Stack](#observability-stack)
- [Kubernetes Resources](#kubernetes-resources)
- [Makefile Reference](#makefile-reference)
- [Troubleshooting](#troubleshooting)
- [macOS Note](#macos-note)
- [License](#license)

---

## Architecture Overview

```
                          ┌─────────────────────────────────────┐
                          │            Client / Browser          │
                          └──────────────┬──────────────────────┘
                                         │
                          ┌──────────────▼──────────────────────┐
                          │      NGINX Ingress Controller       │
                          │      (L7 routing, path-based)       │
                          └──┬──────────┬──────────────┬────────┘
                             │          │              │
               /fastify/*   │  /nextjs/*│   /fastapi/* │
                             │          │              │
                  ┌──────────▼──┐ ┌─────▼─────┐ ┌─────▼──────┐
                  │  Fastify    │ │  Next.js   │ │  FastAPI   │
                  │  :3001      │ │  :3002     │ │  :8000     │
                  │  TypeScript │ │  App Router│ │  Python    │
                  └──────┬──────┘ └─────┬──────┘ └─────┬──────┘
                         │              │              │
                         │    OTLP/HTTP (traces+metrics)
                         │              │              │
                  ┌──────▼──────────────▼──────────────▼──────┐
                  │        OpenTelemetry Collector :4318       │
                  │  (receives OTLP, exports to Prometheus)   │
                  └──────────────────┬────────────────────────┘
                                     │
            ┌────────────────────────┼───────────────────┐
            │                        │                   │
    ┌───────▼────────┐    ┌──────────▼──────┐   ┌───────▼───────┐
    │ Prometheus      │    │  Grafana        │   │   Loki        │
    │ :9090           │    │  :3000          │   │   :3100       │
    │ (metrics store) │    │  (dashboards)   │   │   (log store) │
    └────────────────┘    └─────────────────┘   └───────▲───────┘
                                                        │
                                                ┌───────┴───────┐
                                                │  Fluent Bit   │
                                                │  :24224       │
                                                │  (log fwd)    │
                                                └───────────────┘
```

**Data flow summary:**
1. Clients hit the NGINX Ingress, which routes by path prefix to the correct service.
2. Each service emits OpenTelemetry traces and metrics via OTLP/HTTP to the OTel Collector.
3. The OTel Collector batches and exports metrics to Prometheus (pull via scrape endpoint on `:8889`).
4. Prometheus also directly scrapes each service's `/metrics` endpoint (Prometheus client library).
5. Container stdout/stderr logs flow through Fluent Bit to Loki.
6. Grafana queries both Prometheus and Loki for unified dashboards.

---

## Tech Stack

### Microservices

| Service | Runtime | Framework | Language | Port | Purpose |
|---------|---------|-----------|----------|------|---------|
| fastify-service | Node.js 20 (Alpine) | Fastify 5 | TypeScript 5 | 3001 | High-performance REST API — items CRUD |
| nextjs-service | Node.js 20 (Alpine) | Next.js 15 (App Router) | TypeScript 5 | 3002 | Full-stack React + API routes — products CRUD |
| fastapi-service | Python 3.12 (Slim) | FastAPI 0.135 + Uvicorn | Python 3.12 | 8000 | Async REST API — orders CRUD |

### Observability

| Tool | Version | Role |
|------|---------|------|
| OpenTelemetry SDK | 1.30+ (JS) / 1.33 (Py) | Distributed tracing + metrics instrumentation inside each service |
| OpenTelemetry Collector | 0.123.0 | Centralized OTLP receiver; batches and re-exports telemetry |
| Prometheus | 3.3.0 | Time-series metrics store; scrapes `/metrics` endpoints every 15s |
| prom-client (JS) / prometheus-fastapi-instrumentator (Py) | 15.x / 7.1 | Per-service Prometheus client libraries exposing `/metrics` |
| Grafana | 11.6.0 | Visualization layer; pre-provisioned with Prometheus + Loki datasources |
| Loki | 3.4.2 | Log aggregation backend (TSDB storage, single-node) |
| Fluent Bit | 4.0 | Lightweight log forwarder; collects Docker logs and pushes to Loki |

### Infrastructure & Orchestration

| Tool | Role |
|------|------|
| Docker + Docker Compose | Local containerization and multi-service orchestration |
| Kubernetes (Kind) | Local multi-node K8s cluster (1 control-plane + 2 workers) |
| Helm 3 | Templated K8s package management; single chart deploys all services |
| NGINX Ingress Controller | L7 reverse proxy + path-based routing inside K8s |
| HPA (Horizontal Pod Autoscaler) | CPU-based autoscaling (70% target, 2-5 replicas per service) |
| KEDA | Optional HTTP-based scaling (scaled objects provided) |
| Terraform 1.5+ | Alternative IaC path — deploys the same Helm chart via `hashicorp/helm` provider |

### CI/CD & Quality

| Tool | Role |
|------|------|
| GitHub Actions (5 workflows) | CI, CD, Helm validation, Dockerfile lint, dependency security audit |
| GitHub Container Registry (GHCR) | OCI image registry; images tagged with git SHA + `latest` |
| Trivy | Container image vulnerability scanning (CRITICAL + HIGH severity) |
| Hadolint | Dockerfile best-practice linter (catches security/performance issues in Dockerfiles) |
| pip-audit / npm audit | Dependency vulnerability scanning (catches CVEs in declared packages) |
| ESLint 9 | Static analysis for TypeScript services |
| Ruff | Fast Python linter (replaces flake8 + isort + pyupgrade) |
| Vitest | Unit test runner for Fastify service |
| Jest 29 + Testing Library | Unit test runner for Next.js service |
| pytest 9 + pytest-asyncio | Async unit test runner for FastAPI service |

---

## Why Each Technology

| Decision | Rationale |
|----------|-----------|
| **Three different frameworks** | Proves deployment tooling is framework-agnostic; exercises Node.js and Python ecosystems |
| **Fastify over Express** | 2-3x throughput advantage; built-in schema validation, plugin system, TypeScript-first |
| **Next.js App Router** | Demonstrates full-stack deployment (SSR + API routes) in a single container |
| **FastAPI** | Native async, automatic OpenAPI docs, Pydantic validation; Python's fastest REST framework |
| **OpenTelemetry (not vendor SDK)** | Vendor-neutral; single instrumentation works with any backend (Jaeger, Datadog, etc.) |
| **Prometheus + prom-client** | Industry standard for K8s metrics; built-in HPA metrics adapter compatibility |
| **Loki + Fluent Bit** | Lightweight log stack (vs. ELK); Loki indexes labels only, Fluent Bit has ~450KB footprint |
| **Kind over Minikube** | Runs real multi-node clusters in Docker containers; works identically on CI and local |
| **Helm over raw manifests** | Parameterized deployments; `values.yaml` updated automatically by CD pipeline |
| **Terraform (optional)** | Demonstrates GitOps-style IaC; same Helm chart, different deployment path |
| **Multi-stage Dockerfiles** | Separates build dependencies from runtime; results in smaller, more secure images |
| **Hadolint** | Only Dockerfile-specific linter; catches issues Trivy misses (layer ordering, missing USER, apt cleanup) |
| **pip-audit + npm audit** | Catches CVEs at the dependency declaration level, before images are built; weekly schedule catches new disclosures |
| **NGINX Ingress** | Most widely adopted K8s ingress controller; battle-tested, extensive documentation |

---

## Project Structure

```
deployServices/
├── .github/workflows/
│   ├── ci.yml                        # CI: lint → test → build → scan → E2E
│   ├── deploy.yml                    # CD: build → push GHCR → update Helm values
│   ├── helm-validate.yml             # Helm lint + template render + dry-run
│   ├── docker-lint.yml               # Hadolint Dockerfile best-practice checks
│   └── security-audit.yml            # npm audit + pip-audit (dependency CVEs)
│
├── services/
│   ├── fastify-service/
│   │   ├── src/
│   │   │   ├── server.ts             # Fastify app bootstrap + error handling
│   │   │   ├── telemetry.ts          # OTel SDK initialization (traces + metrics)
│   │   │   ├── plugins/metrics.ts    # prom-client histogram + /metrics route
│   │   │   └── routes/               # health.ts, items.ts (CRUD endpoints)
│   │   ├── tests/items.test.ts       # Vitest unit tests
│   │   ├── Dockerfile                # Multi-stage: node:20-alpine build → runtime
│   │   ├── package.json
│   │   └── tsconfig.json
│   │
│   ├── nextjs-service/
│   │   ├── src/
│   │   │   ├── app/                  # App Router: layout, page, api/ routes
│   │   │   ├── lib/metrics.ts        # prom-client setup
│   │   │   ├── lib/store.ts          # In-memory data store
│   │   │   └── instrumentation.ts    # OTel SDK (Next.js instrumentation hook)
│   │   ├── __tests__/                # Jest + Testing Library tests
│   │   ├── Dockerfile                # Multi-stage: deps → build → runner (standalone)
│   │   └── package.json
│   │
│   └── fastapi-service/
│       ├── app/
│       │   ├── main.py               # FastAPI app + lifespan (startup/shutdown)
│       │   ├── telemetry.py          # OTel SDK initialization
│       │   └── routes/               # health.py, orders.py (CRUD endpoints)
│       ├── tests/test_orders.py      # pytest-asyncio tests
│       ├── Dockerfile                # Multi-stage: python:3.12-slim build → runtime
│       └── requirements.txt
│
├── monitoring/
│   ├── prometheus/prometheus.yml      # Scrape config: services + OTel collector
│   ├── grafana/datasources.yml        # Auto-provisioned Prometheus + Loki sources
│   ├── otel-collector/otel-collector-config.yaml
│   ├── loki/loki-config.yaml          # Single-node TSDB config
│   └── fluent-bit/                    # fluent-bit.conf + parsers.conf
│
├── k8s/                               # Raw K8s manifests (namespace, deploy, svc, hpa,
│                                      #   network policy, ingress) — used as reference
├── helm/deploy-services/
│   ├── Chart.yaml
│   ├── values.yaml                    # Image repos, tags, replicas, resources, probes
│   └── templates/                     # Deployment, Service, HPA, Ingress, ConfigMap
│
├── terraform/
│   ├── providers.tf                   # hashicorp/kubernetes + hashicorp/helm providers
│   ├── variables.tf                   # image_tag, replica counts, kubeconfig path
│   ├── main.tf                        # helm_release resource
│   └── outputs.tf
│
├── scripts/
│   ├── kind-config.yaml               # 3-node cluster (1 CP + 2 workers), port mappings
│   ├── setup-kind.sh / .ps1           # Cluster creation + NGINX Ingress install
│   └── deploy.sh / .ps1               # Build → load → Helm install
│
├── tests/e2e/run.sh                   # E2E test suite (health, CRUD, errors, metrics)
├── docker-compose.yml                 # Full local stack (services + monitoring)
├── docker-compose.logging.yml         # Optional: Fluentd log driver overlay
├── Makefile                           # Unified CLI for all operations
└── .gitignore
```

---

## Prerequisites (Windows)

> All commands below assume **PowerShell** or **Git Bash** on Windows 10/11.

### Step 1 — Install Required Tools

| Tool | Install Command (winget) | What It Does |
|------|--------------------------|--------------|
| Docker Desktop | [Download installer](https://docs.docker.com/desktop/install/windows-install/) | Container runtime + Docker Compose engine |
| Git (includes Bash + Make) | `winget install Git.Git` | Version control + GNU Make via Git Bash |
| Node.js 20+ | `winget install OpenJS.NodeJS.LTS` | JavaScript runtime for Fastify and Next.js services |
| Python 3.12+ | `winget install Python.Python.3.12` | Python runtime for FastAPI service |
| Kind | `winget install Kubernetes.kind` | Local multi-node K8s clusters inside Docker |
| kubectl | `winget install Kubernetes.kubectl` | Kubernetes CLI |
| Helm | `winget install Helm.Helm` | Kubernetes package manager |
| Trivy *(optional)* | `winget install AquaSecurity.Trivy` | Container image vulnerability scanner |
| Terraform *(optional)* | `winget install Hashicorp.Terraform` | Infrastructure as Code (alternative deploy path) |

### Step 2 — Verify Installations

Open a **new terminal** (PowerShell or Git Bash) and run:

```bash
docker --version          # Docker Desktop 4.x
docker compose version    # Docker Compose v2.x (built into Docker Desktop)
node --version            # v20.x or higher
python --version          # Python 3.12.x
kind --version            # kind v0.x
kubectl version --client  # Client Version: v1.x
helm version --short      # v3.x
```

### Step 3 — Start Docker Desktop

Ensure Docker Desktop is running before executing any commands. The Docker daemon must be active for both Docker Compose and Kind to function.

```powershell
# Windows — Docker Desktop auto-starts on login, or launch manually
Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe"
```

### Step 4 — Clone the Repository

```bash
git clone https://github.com/sanjeev0120test/deployServices.git
cd deployServices
```

---

## Getting Started — Local (Windows)

> Use **Git Bash** for all `make` commands. PowerShell works for `docker`, `kind`, `kubectl`, `helm` commands directly.

### Option A: Docker Compose

**What it does:** Builds all three microservices from their Dockerfiles and starts them alongside the full observability stack (Prometheus, Grafana, Loki, Fluent Bit, OTel Collector) in isolated containers on a shared Docker network.

```bash
# 1. Build images and start all 9 containers
make up
# Equivalent: docker compose up -d --build

# 2. Verify all services are running
docker compose ps

# 3. Test endpoints
curl http://localhost:3001/health          # Fastify
curl http://localhost:3002/api/health      # Next.js
curl http://localhost:8000/health          # FastAPI

# 4. Run the full E2E test suite
make e2e

# 5. Open Grafana for dashboards
#    http://localhost:3000  (login: admin / admin)

# 6. Tear down when done
make down
```

**Service URLs after `make up`:**

| Service | URL | Description |
|---------|-----|-------------|
| Fastify API | http://localhost:3001 | Items CRUD + health + metrics |
| Next.js App | http://localhost:3002 | Products CRUD + dashboard UI |
| FastAPI | http://localhost:8000 | Orders CRUD + auto OpenAPI docs at `/docs` |
| Prometheus | http://localhost:9090 | Query metrics, check scrape targets |
| Grafana | http://localhost:3000 | Dashboards (admin/admin) |
| Loki | http://localhost:3100 | Log query API |
| OTel Collector | http://localhost:4318 | OTLP HTTP receiver |

---

### Option B: Kubernetes via Kind

**What it does:** Creates a local 3-node Kubernetes cluster (1 control-plane + 2 workers) inside Docker containers, installs the NGINX Ingress Controller, builds Docker images, loads them into the cluster, and deploys all services via Helm with proper resource limits, health probes, HPA, and network policies.

```bash
# 1. Create the Kind cluster (3 nodes) + install NGINX Ingress Controller
make kind-create
#    └── kind create cluster --config scripts/kind-config.yaml
#    └── kubectl apply -f ingress-nginx/deploy.yaml
#    └── kubectl wait --for=condition=ready (ingress controller pod)

# 2. Build Docker images, load into Kind, deploy with Helm
make k8s-deploy
#    └── docker build (3 services)
#    └── kind load docker-image (3 services)
#    └── helm upgrade --install deploy-services helm/deploy-services

# 3. Verify pods, services, and ingress
make k8s-status
# Or directly:
kubectl get pods,svc,ingress -n deploy-services

# 4. Test through the Ingress (all services via port 80)
curl http://localhost/fastify/api/items
curl http://localhost/nextjs/api/products
curl http://localhost/fastapi/api/orders

# 5. Run E2E tests against Kind Ingress
make k8s-e2e

# 6. Cleanup
make k8s-delete     # Uninstall Helm release + delete namespace
make kind-delete    # Delete the Kind cluster entirely
```

**Kind Cluster Topology:**

```
┌─────────────────────────────────────────────────┐
│  Kind Cluster: deploy-services                  │
│                                                 │
│  ┌─────────────────────┐                        │
│  │ Control Plane        │  Port 80  → host:80   │
│  │ NGINX Ingress ✓      │  Port 443 → host:443  │
│  │ label: ingress-ready │                        │
│  └─────────────────────┘                        │
│                                                 │
│  ┌──────────┐  ┌──────────┐                     │
│  │ Worker 1 │  │ Worker 2 │                     │
│  │ pods run │  │ pods run │                     │
│  │ here     │  │ here     │                     │
│  └──────────┘  └──────────┘                     │
└─────────────────────────────────────────────────┘
```

---

### Option C: Terraform

**What it does:** Uses the HashiCorp Helm Terraform provider to deploy the exact same Helm chart as Option B, but through Terraform's declarative state management. Useful for practicing IaC workflows.

> **Prerequisite:** A Kind cluster must already be running (complete Step 1 from Option B first).

```bash
cd terraform

# 1. Initialize providers (downloads hashicorp/kubernetes + hashicorp/helm)
terraform init

# 2. Preview the execution plan
terraform plan

# 3. Apply — deploys the Helm release into the Kind cluster
terraform apply

# 4. Override defaults if needed
terraform apply -var="image_tag=abc123" -var="fastify_replicas=3"

# 5. Destroy when done
terraform destroy
```

---

## Running Tests

### Unit Tests

Each service includes focused unit tests covering CRUD operations, error handling, and edge cases.

```bash
make test               # Run all 3 services
make test-fastify       # Vitest   → services/fastify-service
make test-nextjs        # Jest     → services/nextjs-service
make test-fastapi       # pytest   → services/fastapi-service
```

### Linting

```bash
make lint               # Run all 3 services
make lint-fastify       # ESLint   → TypeScript (Fastify)
make lint-nextjs        # ESLint   → TypeScript (Next.js)
make lint-fastapi       # Ruff     → Python (FastAPI)
```

### E2E Tests

The E2E test suite (`tests/e2e/run.sh`) performs the following validations against live running services:

| Check | What It Validates |
|-------|-------------------|
| Health probes | `GET /health` returns 200 on all services |
| Readiness probes | `GET /ready` returns 200 on all services |
| List endpoints | `GET /api/items`, `/api/products`, `/api/orders` return 200 + JSON array |
| Create endpoints | `POST` with valid JSON returns 201 + created resource |
| Get by ID | `GET /api/{resource}/{id}` returns 200 + correct entity |
| Error handling | Invalid IDs return 404; malformed payloads return 400 |
| Prometheus metrics | `GET /metrics` returns 200 + contains `http_request` metrics |

```bash
make e2e                # Against Docker Compose (localhost:3001, :3002, :8000)
make k8s-e2e            # Against Kind Ingress   (localhost/fastify, /nextjs, /fastapi)
```

---

## CI/CD — GitHub Actions

This project ships with **5 GitHub Actions workflows**, each serving a distinct purpose. All support `workflow_dispatch` for manual runs from the Actions tab.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         GitHub Actions Workflows                            │
│                                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐       │
│  │   ci.yml    │  │ deploy.yml  │  │helm-validate│  │ docker-lint │       │
│  │             │  │             │  │    .yml     │  │    .yml     │       │
│  │ lint→test→  │  │ build+push  │  │ helm lint   │  │ hadolint    │       │
│  │ build→scan→ │  │ to GHCR →   │  │ + template  │  │ on all 3    │       │
│  │ E2E        │  │ update Helm │  │ + dry-run   │  │ Dockerfiles │       │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘       │
│                                                                             │
│  ┌─────────────────────┐                                                    │
│  │ security-audit.yml  │                                                    │
│  │                     │                                                    │
│  │ npm audit (2x)      │                                                    │
│  │ pip-audit (1x)      │                                                    │
│  │ + weekly schedule   │                                                    │
│  └─────────────────────┘                                                    │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1. CI Pipeline (`ci.yml`)

**Why:** Validates that every code change passes linting, tests, builds, security scans, and end-to-end verification before it can be considered safe to deploy.

**Triggers:** `push` to main, `pull_request` to main, `workflow_dispatch`

```
┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐
│   Lint   │     │   Test   │     │  Build   │     │   Scan   │     │   E2E    │
│          │     │          │     │          │     │          │     │          │
│ ESLint   │────►│ Vitest   │────►│ docker   │────►│ Trivy    │────►│ Compose  │
│ Ruff     │     │ Jest     │     │ build    │     │ HIGH +   │     │ health   │
│          │     │ pytest   │     │ + save   │     │ CRITICAL │     │ CRUD     │
│ 3×parallel    │ 3×parallel    │ 3×parallel    │ 3×parallel    │ metrics  │
└──────────┘     └──────────┘     └──────────┘     └──────────┘     └──────────┘
```

| Stage | Job | What It Does | Why |
|-------|-----|--------------|-----|
| 1 | **Lint** (3x matrix) | ESLint (Node.js) or Ruff (Python) | Catches syntax errors and code style violations before tests run |
| 2 | **Test** (3x matrix) | Vitest, Jest, or pytest | Verifies business logic and CRUD operations work correctly |
| 3 | **Build** (3x matrix) | Multi-stage Docker build, saves as tar artifact | Confirms Dockerfiles produce valid images; artifacts reused by scan + E2E |
| 4 | **Scan** (3x matrix) | Trivy vulnerability scan (CRITICAL + HIGH) | Detects OS-level and library CVEs inside the built container images |
| 5 | **E2E** | Docker Compose up → health check → full test suite | Validates all 3 services work together end-to-end in a real container environment |

### 2. CD Pipeline (`deploy.yml`)

**Why:** Automates the build-tag-push-update cycle so that every merge to `main` produces deployable container images in GHCR and updates the Helm chart to reference them. This is the foundation for GitOps-style continuous deployment.

**Triggers:** `push` to main, `workflow_dispatch`

```
┌──────────────────────┐     ┌──────────────────────────┐
│  Build & Push (3x)   │     │  Update Helm Manifests   │
│                      │     │                          │
│  docker build        │────►│  sed update values.yaml  │
│  docker push GHCR    │     │  git commit + push       │
│  :sha + :latest      │     │  (auto-commit by CI)     │
└──────────────────────┘     └──────────────────────────┘
```

| Stage | What It Does | Why |
|-------|--------------|-----|
| **Build & Push** (3x matrix) | Builds each service, pushes to `ghcr.io/<owner>/<repo>/<service>` with git SHA + `latest` tags | Immutable image tags tied to specific commits enable reliable rollbacks |
| **Update Helm Manifests** | Updates `values.yaml` with new image references, auto-commits to `main` | Keeps Helm chart always pointing to the latest validated images |

**Image naming convention:**
```
ghcr.io/sanjeev0120test/deployservices/fastify-service:<git-sha>
ghcr.io/sanjeev0120test/deployservices/fastify-service:latest
```

### 3. Helm Chart Validation (`helm-validate.yml`)

**Why:** A broken Helm chart means failed Kubernetes deployments. This workflow catches YAML syntax errors, missing template values, and invalid K8s resource definitions *before* they reach a cluster. It runs `helm lint --strict` (catches template warnings), `helm template` (renders all templates to verify no missing values), and `kubectl apply --dry-run=client` (validates generated YAML against the K8s API schema).

**Triggers:** `push`/`pull_request` to main (when `helm/**` or `k8s/**` files change), `workflow_dispatch`

| Step | What It Does | Why |
|------|--------------|-----|
| **Helm Lint** | `helm lint --strict` | Catches YAML formatting issues and template warnings |
| **Template Render** | `helm template --debug` | Verifies all templates render without errors |
| **Dry-run Install** | `kubectl apply --dry-run=client` on rendered output | Validates generated manifests against K8s API schema |

### 4. Dockerfile Lint (`docker-lint.yml`)

**Why:** Multi-stage Dockerfiles are a core part of this project. Hadolint catches security issues (running as root, missing `USER` directive), performance issues (unnecessary layers, missing `--no-cache`), and best-practice violations that could lead to bloated or insecure images. It is the industry-standard Dockerfile linter.

**Triggers:** `push`/`pull_request` to main (when any `Dockerfile` changes), `workflow_dispatch`

| Step | What It Does | Why |
|------|--------------|-----|
| **Hadolint** (3x matrix) | Lints each service's Dockerfile at `warning` threshold | Catches Dockerfile anti-patterns that Trivy (image scanner) cannot detect |

### 5. Dependency Security Audit (`security-audit.yml`)

**Why:** Trivy scans *built images* for CVEs, but dependency vulnerabilities are best caught *at the source* — in `package.json` / `requirements.txt`. `npm audit` checks the npm advisory database and `pip-audit` checks the Python Packaging Advisory Database (PyPA). This workflow also runs on a **weekly schedule** to catch newly disclosed CVEs even when no code changes.

**Triggers:** `push`/`pull_request` to main (when dependency files change), `workflow_dispatch`, **weekly (Monday 08:00 UTC)**

| Job | What It Does | Why |
|-----|--------------|-----|
| **npm audit** (2x matrix) | `npm audit` on fastify-service and nextjs-service | Detects known CVEs in JavaScript dependencies |
| **pip-audit** | `pip-audit -r requirements.txt` on fastapi-service | Detects known CVEs in Python dependencies |

### Setting Up CI/CD for Your Fork

1. **Fork** the repository on GitHub.
2. Go to **Settings → Actions → General → Workflow permissions** → select **Read and write permissions**.
   - **Why:** The Deploy workflow needs `packages: write` to push images to GHCR and `contents: write` to auto-commit Helm values updates.
3. Push to `main` or manually trigger workflows from the **Actions** tab.
4. No secrets configuration needed — `GITHUB_TOKEN` is auto-provided by GitHub Actions with the permissions specified in each workflow file.

---

## Service API Reference

### fastify-service (`:3001`)

| Method | Path | Request Body | Response | Description |
|--------|------|-------------|----------|-------------|
| `GET` | `/health` | — | `{"status":"ok"}` | Liveness probe |
| `GET` | `/ready` | — | `{"status":"ready"}` | Readiness probe |
| `GET` | `/metrics` | — | Prometheus text format | prom-client metrics |
| `GET` | `/api/items` | — | `[{id, name, description, createdAt}]` | List all items |
| `GET` | `/api/items/:id` | — | `{id, name, description, createdAt}` | Get item by ID |
| `POST` | `/api/items` | `{"name":"...","description":"..."}` | `{id, name, description, createdAt}` (201) | Create item |

### nextjs-service (`:3002`)

| Method | Path | Request Body | Response | Description |
|--------|------|-------------|----------|-------------|
| `GET` | `/api/health` | — | `{"status":"ok"}` | Liveness probe |
| `GET` | `/api/ready` | — | `{"status":"ready"}` | Readiness probe |
| `GET` | `/api/metrics` | — | Prometheus text format | prom-client metrics |
| `GET` | `/api/products` | — | `[{id, name, price, category, createdAt}]` | List all products |
| `GET` | `/api/products/[id]` | — | `{id, name, price, category, createdAt}` | Get product by ID |
| `POST` | `/api/products` | `{"name":"...","price":9.99,"category":"..."}` | `{id, ...}` (201) | Create product |
| `GET` | `/` | — | HTML page | Dashboard UI |

### fastapi-service (`:8000`)

| Method | Path | Request Body | Response | Description |
|--------|------|-------------|----------|-------------|
| `GET` | `/health` | — | `{"status":"ok"}` | Liveness probe |
| `GET` | `/ready` | — | `{"status":"ready"}` | Readiness probe |
| `GET` | `/metrics` | — | Prometheus text format | Instrumentator metrics |
| `GET` | `/api/orders` | — | `[{id, customer, item, quantity, status, created_at}]` | List all orders |
| `GET` | `/api/orders/{id}` | — | `{id, customer, item, quantity, status, created_at}` | Get order by ID |
| `POST` | `/api/orders` | `{"customer":"...","item":"...","quantity":1}` | `{id, ...}` (201) | Create order |
| `GET` | `/docs` | — | HTML page | Auto-generated OpenAPI docs |

---

## Observability Stack

### How Telemetry Flows

```
Service code                    OTel Collector              Backends
──────────────                  ──────────────              ────────
@opentelemetry/sdk-node    ──OTLP/HTTP──►  receivers.otlp
                                            │
                                            ├──► exporters.prometheus ──► Prometheus :9090
                                            └──► exporters.debug     ──► stdout (debug)

prom-client / instrumentator ──────────────────────────────► Prometheus :9090
                                                             (direct /metrics scrape)

Docker container logs ──► Fluent Bit :24224 ──► Loki :3100

Grafana :3000 ──queries──► Prometheus (metrics)
              ──queries──► Loki (logs)
```

### OpenTelemetry Configuration

- **Receiver:** OTLP HTTP on `:4318` (all three services send traces and metrics here)
- **Processor:** Batch processor — 5s timeout, 1024 batch size (reduces network overhead)
- **Exporters:** Prometheus exporter on `:8889` (scraped by Prometheus) + Debug exporter (stdout for troubleshooting)
- **Traces pipeline:** `otlp → batch → debug`
- **Metrics pipeline:** `otlp → batch → prometheus`

### Prometheus Scrape Targets

| Target | Endpoint | Interval |
|--------|----------|----------|
| fastify-service | `fastify-service:3001/metrics` | 15s |
| nextjs-service | `nextjs-service:3002/api/metrics` | 15s |
| fastapi-service | `fastapi-service:8000/metrics` | 15s |
| otel-collector | `otel-collector:8889/metrics` | 15s |

### Grafana

Pre-provisioned with two datasources (no manual setup required):

| Datasource | URL | Type |
|------------|-----|------|
| Prometheus | `http://prometheus:9090` | Metrics (PromQL) |
| Loki | `http://loki:3100` | Logs (LogQL) |

Access at **http://localhost:3000** — default credentials: `admin` / `admin`

---

## Kubernetes Resources

Each service is deployed with the following K8s resources via Helm:

| Resource | Purpose |
|----------|---------|
| **Deployment** | 2 replicas per service; rolling update strategy; `securityContext` (non-root, read-only rootfs where possible) |
| **Service** | ClusterIP; maps service port to container port |
| **HPA** | Scales 2→5 replicas at 70% CPU utilization |
| **ConfigMap** | Environment variables (PORT, OTEL_*, NODE_ENV) |
| **Ingress** | NGINX class; path-based routing with regex rewrite: `/fastify(/\|$)(.*)` → `/$2` |
| **NetworkPolicy** | Restricts ingress to only NGINX controller; denies unexpected traffic |
| **Namespace** | `deploy-services` — isolates all resources |

**Resource Limits (per pod):**

| | CPU Request | CPU Limit | Memory Request | Memory Limit |
|---|-------------|-----------|----------------|--------------|
| All services | 100m | 250m | 128Mi | 256Mi |

---

## Makefile Reference

> Run all `make` commands from **Git Bash** on Windows.

| Command | Description |
|---------|-------------|
| `make help` | Show all available targets |
| `make build` | Build all 3 Docker images locally |
| `make up` | `docker compose up -d --build` — start full stack |
| `make down` | `docker compose down -v` — stop and remove volumes |
| `make logs` | `docker compose logs -f` — tail all container logs |
| `make lint` | Run ESLint (Fastify, Next.js) + Ruff (FastAPI) |
| `make test` | Run Vitest + Jest + pytest |
| `make e2e` | E2E tests against Docker Compose |
| `make scan` | Trivy scan all 3 images (HIGH + CRITICAL) |
| `make kind-create` | Create Kind cluster + install NGINX Ingress |
| `make kind-delete` | Delete Kind cluster |
| `make kind-load` | Build + load images into Kind |
| `make k8s-deploy` | Build, load, Helm install into Kind |
| `make k8s-delete` | Uninstall Helm release + delete namespace |
| `make k8s-status` | Show pods, services, ingress |
| `make k8s-e2e` | E2E tests against Kind Ingress |
| `make clean` | Remove build artifacts (dist, .next, __pycache__) |

---

## Troubleshooting

### Port 80 already in use (Windows)

Kind maps port 80 from the control-plane container to your host. If another process is using port 80:

```powershell
netstat -ano | findstr :80
# Identify the PID and stop the conflicting process, or
# edit scripts/kind-config.yaml to change hostPort to a different value
```

### Docker Compose Fluentd driver error

If services fail to start with "fluentd driver not found", the optional Fluentd logging overlay is enabled. Use the base compose file only:

```bash
docker compose up -d        # Uses docker-compose.yml (no Fluentd driver)
```

To explicitly enable Fluent Bit log forwarding:

```bash
docker compose -f docker-compose.yml -f docker-compose.logging.yml up -d
```

### Kind images not found / ImagePullBackOff

Kind runs its own container registry. Images must be loaded into Kind after building:

```bash
make kind-load    # Builds all images + kind load docker-image for each
```

### Terraform state

Terraform state is stored locally at `terraform/terraform.tfstate`. This file is gitignored. Do not commit it — it may contain sensitive cluster connection details.

### Services not responding after `make up`

Wait 15-20 seconds for health checks to pass. Check container status:

```bash
docker compose ps           # Check STATUS column
docker compose logs <name>  # Check specific service logs
```

---

## macOS Note

> This project is built and tested on **Windows + Docker Desktop + GitHub Actions (Ubuntu)**. It is compatible with macOS with the following adjustments:

**Install prerequisites:**

```bash
brew install kind kubectl helm node python@3.12 trivy terraform
```

**Key differences:**
- Docker Desktop for Mac must be running (same as Windows).
- Port 80 binding may require `sudo` — verify with `lsof -i :80`.
- GNU Make is pre-installed on macOS (no additional setup).
- All shell scripts and Makefile targets use standard `bash` and are cross-platform.
- `winget` commands in prerequisites do not apply — use `brew` instead.

---

## License

[MIT](LICENSE)
