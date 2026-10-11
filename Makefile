.PHONY: help test lint run build docker-run observe \
        k8s-up k8s-down k8s-status k8s-load \
        chaos-errors chaos-latency chaos-kill chaos-outage chaos-off \
        policy-test alert-test k8s-validate fmt validate plan plan-policy release clean

ENV ?= dev
TF  := terraform -chdir=infra/envs/$(ENV)

# Use python3 if a bare `python` isn't on PATH (e.g. Ubuntu / WSL2).
PYTHON := $(shell command -v python 2>/dev/null || command -v python3)
PIP    := $(PYTHON) -m pip

help: ## Show this help
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

# --- app -------------------------------------------------------------------
test: ## Run app unit tests
	cd app && $(PIP) install -q -r requirements.txt -r requirements-dev.txt && $(PYTHON) -m pytest -q

lint: ## Lint the app
	cd app && $(PYTHON) -m ruff check .

run: ## Run the app from source on :8000 (auto-reload)
	cd app && MOCK_LLM=true $(PYTHON) -m uvicorn main:app --reload

build: ## Build the container image
	docker build --build-arg VERSION=local -t agentic-gp:local app

docker-run: build ## Run the container on :8000
	docker run --rm -p 8000:8000 --name agent agentic-gp:local

observe: ## Docker Compose: app + Prometheus (:9090) + Grafana (:3000)
	docker compose up --build

# --- local Kubernetes track (kind) ------------------------------------------
k8s-up: ## Create kind cluster + monitoring + logs + app + ArgoCD
	./scripts/setup.sh

k8s-down: ## Delete the kind cluster and stop port-forwards
	./scripts/teardown.sh

k8s-status: ## Pods, ArgoCD sync state, firing alerts
	./scripts/status.sh

k8s-load: ## Steady traffic against the cluster (Ctrl+C to stop)
	./scripts/load.sh

chaos-errors: ## Inject 30% errors -> AgentHighErrorRate
	./scripts/chaos.sh errors

chaos-latency: ## Add 1.5s latency -> AgentHighLatencyP95
	./scripts/chaos.sh latency

chaos-kill: ## Delete a pod and watch it come back
	./scripts/chaos.sh kill-pod

chaos-outage: ## Scale to zero -> AgentAllReplicasDown
	./scripts/chaos.sh outage

chaos-off: ## Undo all chaos, re-enable GitOps self-heal
	./scripts/chaos.sh off

# --- policy & validation ----------------------------------------------------
policy-test: ## Unit-test the Rego policies
	conftest fmt --check policy && conftest verify --policy policy

alert-test: ## Unit-test the alert rules (needs promtool, amtool)
	./scripts/test-alerts.sh

k8s-validate: ## Render k8s/ and run the security policy on it
	kubectl kustomize k8s > /tmp/agentic-gp-rendered.yaml
	conftest test --policy policy --namespace k8s /tmp/agentic-gp-rendered.yaml

# --- AWS track --------------------------------------------------------------
fmt: ## Format Terraform
	terraform fmt -recursive infra

validate: ## Validate Terraform for $(ENV) (no backend)
	$(TF) init -backend=false && $(TF) validate

plan: ## Terraform plan for $(ENV) (needs AWS creds + backend)
	$(TF) init && $(TF) plan -var="image_tag=$${IMAGE_TAG:-latest}"

plan-policy: ## Plan + run the Conftest policy gate for $(ENV)
	$(TF) init && $(TF) plan -out=tf.plan -var="image_tag=$${IMAGE_TAG:-latest}"
	$(TF) show -json tf.plan > plan.json
	conftest test --policy policy --namespace main plan.json

# --- release ----------------------------------------------------------------
release: ## Tag a release: make release VERSION=0.3.0
	@test -n "$(VERSION)" || (echo "usage: make release VERSION=x.y.z" && exit 1)
	@echo "$(VERSION)" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$$' || (echo "VERSION must be x.y.z" && exit 1)
	git tag -a "v$(VERSION)" -m "Release v$(VERSION)"
	git push origin "v$(VERSION)"

clean: ## Remove local plan artifacts
	rm -f plan.json /tmp/agentic-gp-rendered.yaml
	find infra -name 'tf.plan' -delete
