SHELL := /bin/bash
.DEFAULT_GOAL := help

# --- Variables (override via env or CLI: make build IMAGE_TAG=v2) ---
CLUSTER_NAME   ?= deploy-services
NAMESPACE      ?= deploy-services
IMAGE_TAG      ?= latest
HELM_RELEASE   ?= deploy-services
HELM_CHART     ?= helm/deploy-services

SERVICES := fastify-service nextjs-service fastapi-service

# ====================================================================
# Help
# ====================================================================
.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

# ====================================================================
# Build
# ====================================================================
.PHONY: build build-fastify build-nextjs build-fastapi
build: build-fastify build-nextjs build-fastapi ## Build all Docker images

build-fastify: ## Build fastify-service image
	docker build -t fastify-service:$(IMAGE_TAG) services/fastify-service

build-nextjs: ## Build nextjs-service image
	docker build -t nextjs-service:$(IMAGE_TAG) services/nextjs-service

build-fastapi: ## Build fastapi-service image
	docker build -t fastapi-service:$(IMAGE_TAG) services/fastapi-service

# ====================================================================
# Docker Compose
# ====================================================================
.PHONY: up down logs
up: ## Start all services with Docker Compose
	docker compose up -d --build

down: ## Stop all services
	docker compose down -v

logs: ## Tail logs for all services
	docker compose logs -f

# ====================================================================
# Lint
# ====================================================================
.PHONY: lint lint-fastify lint-nextjs lint-fastapi
lint: lint-fastify lint-nextjs lint-fastapi ## Lint all services

lint-fastify: ## Lint fastify-service
	cd services/fastify-service && npm run lint

lint-nextjs: ## Lint nextjs-service
	cd services/nextjs-service && npm run lint

lint-fastapi: ## Lint fastapi-service
	cd services/fastapi-service && ruff check app/ tests/

# ====================================================================
# Test
# ====================================================================
.PHONY: test test-fastify test-nextjs test-fastapi
test: test-fastify test-nextjs test-fastapi ## Run all unit tests

test-fastify: ## Test fastify-service
	cd services/fastify-service && npm test

test-nextjs: ## Test nextjs-service
	cd services/nextjs-service && npm test

test-fastapi: ## Test fastapi-service
	cd services/fastapi-service && python -m pytest tests/ -v

# ====================================================================
# E2E
# ====================================================================
.PHONY: e2e k8s-e2e
e2e: ## Run E2E tests against Docker Compose
	bash tests/e2e/run.sh --target docker

k8s-e2e: ## Run E2E tests against Kind Ingress
	bash tests/e2e/run.sh --target kind

# ====================================================================
# Image Scanning
# ====================================================================
.PHONY: scan
scan: build ## Scan all Docker images with Trivy
	@for svc in $(SERVICES); do \
		echo "=== Scanning $$svc ===" ; \
		trivy image --severity HIGH,CRITICAL --exit-code 0 $$svc:$(IMAGE_TAG) ; \
	done

# ====================================================================
# Kind Cluster
# ====================================================================
.PHONY: kind-create kind-delete kind-load
kind-create: ## Create Kind cluster with ingress support
	kind create cluster --name $(CLUSTER_NAME) --config scripts/kind-config.yaml --wait 60s
	kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.1/deploy/static/provider/kind/deploy.yaml
	kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=120s

kind-delete: ## Delete Kind cluster
	kind delete cluster --name $(CLUSTER_NAME)

kind-load: build ## Load Docker images into Kind
	@for svc in $(SERVICES); do \
		kind load docker-image $$svc:$(IMAGE_TAG) --name $(CLUSTER_NAME) ; \
	done

# ====================================================================
# Kubernetes / Helm
# ====================================================================
.PHONY: k8s-deploy k8s-delete k8s-status
k8s-deploy: kind-load ## Deploy to Kind with Helm
	helm upgrade --install $(HELM_RELEASE) $(HELM_CHART) \
		--namespace $(NAMESPACE) \
		--create-namespace \
		--wait --timeout 120s

k8s-delete: ## Uninstall Helm release
	helm uninstall $(HELM_RELEASE) --namespace $(NAMESPACE) || true
	kubectl delete namespace $(NAMESPACE) --ignore-not-found

k8s-status: ## Show pod and ingress status
	kubectl get pods,svc,ingress -n $(NAMESPACE)

# ====================================================================
# Platform guards (mirror .github/workflows/platform-guards.yml locally)
# ====================================================================
.PHONY: platform-check terraform-fmt-check terraform-validate gitleaks-local actionlint-local shellcheck-local
platform-check: terraform-fmt-check terraform-validate shellcheck-local actionlint-local gitleaks-local ## Run Terraform fmt/validate, shellcheck, actionlint, gitleaks (requires tools on PATH; use Git Bash/WSL on Windows)

terraform-fmt-check: ## Terraform fmt check (terraform/ directory)
	terraform -chdir=terraform fmt -check -recursive

terraform-validate: ## Terraform init (no backend) and validate
	terraform -chdir=terraform init -backend=false -input=false
	terraform -chdir=terraform validate

gitleaks-local: ## Scan repo for secrets (install: https://github.com/gitleaks/gitleaks )
	@command -v gitleaks >/dev/null 2>&1 || { echo "gitleaks not found. Install: https://github.com/gitleaks/gitleaks#installing"; exit 1; }
	gitleaks detect --source . --redact --verbose

actionlint-local: ## Lint GitHub Actions workflows (install: https://github.com/rhysd/actionlint )
	@command -v actionlint >/dev/null 2>&1 || { echo "actionlint not found. Install: https://github.com/rhysd/actionlint"; exit 1; }
	actionlint

shellcheck-local: ## Shellcheck scripts used for E2E and Kind
	@command -v shellcheck >/dev/null 2>&1 || { echo "shellcheck not found. Install: https://www.shellcheck.net/"; exit 1; }
	shellcheck tests/e2e/run.sh scripts/deploy.sh scripts/setup-kind.sh

# ====================================================================
# Clean
# ====================================================================
.PHONY: clean
clean: ## Remove build artifacts and caches
	rm -rf services/fastify-service/dist
	rm -rf services/nextjs-service/.next services/nextjs-service/out
	rm -rf services/fastapi-service/__pycache__ services/fastapi-service/.pytest_cache
	rm -rf services/fastapi-service/app/__pycache__ services/fastapi-service/app/routes/__pycache__
