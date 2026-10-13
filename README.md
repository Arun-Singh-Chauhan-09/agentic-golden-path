# Agentic Golden Path

A paved road that takes an **agentic (LLM-backed) microservice** from
`git push` to a running, observable, policy-checked service, without anyone
doing those steps by hand.

The app in `app/` is deliberately small (a FastAPI service that mimics a
Bedrock-backed procurement agent). **The platform around it is the point**:
infrastructure as code, CI/CD, GitOps, security gates, SLOs and alerting.

It runs on two tracks that share the same app, image, dashboard and policies:

| | Local Kubernetes track | AWS track |
|---|---|---|
| Runs on | kind on your laptop, free | ECS Fargate, ALB, RDS, Redis |
| Provisioned by | Terraform (`infra/local-kind`) | Terraform (`infra/envs/dev`, `prod`) |
| Deployed by | ArgoCD (GitOps) | GitHub Actions + ECS circuit breaker |
| Observed with | Prometheus, Alertmanager, Grafana, Loki | CloudWatch alarms + SNS |
| Start with | `make k8s-up` | `make plan ENV=dev` (needs an AWS account) |

---

## Local Kubernetes track

### Architecture

```mermaid
graph LR
    dev["git tag vX.Y.Z"] --> rel["release.yml<br/>build image, SBOM, provenance"]
    rel -->|push| ghcr["GHCR"]
    rel -->|commit newTag| repo["k8s/ on main"]
    repo -->|watches| argo["ArgoCD<br/>auto-sync, self-heal"]
    subgraph kind["kind cluster (Terraform)"]
        argo -->|deploys| app["agentic-gp<br/>2 pods, restricted PSS"]
        prom["Prometheus"] -->|scrape /metrics| app
        prom --> rules["SLO rules"] --> am["Alertmanager"]
        pt["Promtail"] -.->|tail stdout| app
        pt --> loki["Loki"]
        graf["Grafana"] --> prom
        graf --> loki
    end
    ghcr -->|pull| app
```

### Prerequisites (WSL2 / Ubuntu)

Docker Desktop with WSL integration enabled, then:

```bash
# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install kubectl /usr/local/bin/ && rm kubectl
# kind
curl -Lo kind https://kind.sigs.k8s.io/dl/v0.24.0/kind-linux-amd64 && sudo install kind /usr/local/bin/ && rm kind
# helm
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

Terraform is optional (the setup falls back to `kind create cluster`).
Conftest is optional (only for `make policy-test` / `make k8s-validate`).

### Run it

```bash
make k8s-up        # ~5-8 minutes on first run
```

`scripts/setup.sh` is idempotent and does, in order: create the cluster →
build the image and load it into kind → install kube-prometheus-stack → install
Loki → apply `k8s/` → install ArgoCD and register the app → start
port-forwards → verify. Every kubectl and helm call is pinned to the
`kind-agentic-gp` context, so other clusters in your kubeconfig are never
touched.

| Service | URL | Login |
|---|---|---|
| App | http://localhost:8090 (`/docs` for the API UI) | |
| Grafana | http://localhost:3030 | admin / admin |
| Prometheus | http://localhost:9090/alerts | |
| Alertmanager | http://localhost:9093 | |
| ArgoCD | https://localhost:8443 | admin / printed by setup |

`make k8s-status` shows pods, the running image, ArgoCD sync state and the
alerts firing right now. `make k8s-down` deletes the cluster.

After a reboot the kind nodes start again with Docker, but port-forwards do
not survive. Run `make k8s-up` again: it is idempotent, so it
leaves the running cluster as it is and restarts the port-forwards. To pause the cluster without losing anything:
`docker stop agentic-gp-control-plane agentic-gp-worker` (and `docker start`
to resume).

### The 10-minute demo

```bash
# terminal 1: traffic, so the graphs and alerts have data
make k8s-load

# terminal 2
make chaos-errors     # 30% of /agent calls fail
                      # Grafana: error ratio jumps over the 0.5% SLO line
                      # ~3 min: AgentHighErrorRate fires (critical) in Alertmanager
                      # Grafana logs panel: the failing requests, as JSON, from Loki
make chaos-off        # recover; ArgoCD self-heal is switched back on

make chaos-latency    # +1.5 s per call -> p95 crosses 1 s -> AgentHighLatencyP95
make chaos-off

make chaos-kill       # delete a pod: ReplicaSet replaces it, PDB keeps 1 serving
make chaos-outage     # scale to 0 -> AgentAllReplicasDown (critical)
make chaos-off
```

**GitOps drift correction:** with self-heal on, try
`kubectl --context kind-agentic-gp -n agentic-gp scale deploy/agentic-gp --replicas=5`
and watch ArgoCD put it back to 2 within seconds. Git is the source of truth.

#### What the chaos targets do

Every target runs `scripts/chaos.sh <mode>`, which uses the same pinned
kubectl context:

| Target | What it changes | What you should see |
|---|---|---|
| `chaos-errors` | self-heal off, `FAILURE_RATE=0.3` | AgentHighErrorRate (critical) after ~2-3 min |
| `chaos-latency` | self-heal off, `EXTRA_LATENCY_MS=1500` | AgentHighLatencyP95 (warning) |
| `chaos-kill` | deletes one pod | replacement pod, no alert (the other pod keeps serving) |
| `chaos-outage` | self-heal off, replicas 0 | AgentAllReplicasDown (critical) after ~1 min |
| `chaos-off` | knobs to 0, replicas 2, self-heal on | alerts resolve once the 5 m windows are clean |

Self-heal has to be paused first: otherwise ArgoCD sees that the cluster no
longer matches Git and undoes the change within seconds, so no alert fires.

#### The outage drill by hand

The same thing `make chaos-outage` / `make chaos-off` do, step by step:

```bash
# 1. pause GitOps self-heal
kubectl --context kind-agentic-gp patch application agentic-gp -n argocd --type merge \
  -p '{"spec":{"syncPolicy":{"automated":{"selfHeal":false}}}}'

# 2. take the app down: localhost:9090/alerts goes INACTIVE -> PENDING -> FIRING
kubectl --context kind-agentic-gp scale deploy/agentic-gp -n agentic-gp --replicas=0

# 3. localhost:9093: AgentAllReplicasDown routed to the "critical" receiver;
#    inhibition hides the per-pod and SLO warnings it implies

# 4. recover and hand control back to Git
kubectl --context kind-agentic-gp scale deploy/agentic-gp -n agentic-gp --replicas=2
kubectl --context kind-agentic-gp patch application agentic-gp -n argocd --type merge \
  -p '{"spec":{"syncPolicy":{"automated":{"selfHeal":true}}}}'
```

### Query it

In Grafana → **Explore**, pick the data source, switch the editor from
*Builder* to *Code*, paste a query and press Shift+Enter. Run `make k8s-load`
first so there is traffic.

**Prometheus (metrics)**

```promql
up{job="agentic-gp"}                                                            # per-pod liveness
sum(rate(agent_requests_total{job="agentic-gp"}[5m]))                           # requests/s
sum by (pod) (rate(agent_requests_total{job="agentic-gp"}[5m]))                 # requests/s per pod
sum by (status) (rate(agent_requests_total{job="agentic-gp",handler="/agent"}[5m]))  # 200 vs 500
agentic_gp:agent_error_ratio:rate5m                                             # SLI: error ratio
agentic_gp:agent_latency_p95:rate5m                                             # SLI: p95 latency (s)
agent_build_info{job="agentic-gp"}                                              # version per pod
```

**Loki (logs)**

```logql
{namespace="agentic-gp"}                                         # everything
{namespace="agentic-gp"} |= "{" | json                           # JSON request logs, parsed
{namespace="agentic-gp"} |= "{" | json | latency_ms > 200        # slow requests
{namespace="agentic-gp"} |= "{" | json | status >= 500           # failed requests
sum by (pod) (count_over_time({namespace="agentic-gp"} |= "{" | json [1m]))  # lines/min per pod
```

`|= "{"` keeps only the app's JSON lines and skips uvicorn's plain-text
access log. Health checks and scrapes are not logged on purpose.

### Shipping a version

```bash
git pull
# change code, then:
make test
git add . && git commit -m "feat: ..." && git push     # CI runs on main
# wait for CI to be green (GitHub -> Actions -> ci), then:
git tag v0.3.2 && git push origin v0.3.2                # or: make release VERSION=0.3.2
git pull                                                # fetch the bot's newTag commit
curl -s localhost:8090/health                           # "version":"0.3.2" after the rollout
```

```
git push origin vX.Y.Z
  |
  v
release.yml: build image (+ SBOM, provenance) -> push to GHCR
  |
  v
bot commits newTag: X.Y.Z in k8s/kustomization.yaml -> GitHub Release
  |
  v
ArgoCD polls Git (~3 min, or "Refresh" in the UI) -> OutOfSync -> auto-sync
  |
  v
rolling update: a new pod must pass /ready before an old one stops
```

`maxUnavailable: 0` plus the readiness probe mean capacity never drops during
the rollout, and `agent_build_info` shows both versions side by side while it
runs. A version number can be tagged only once. If new pods sit in
`ImagePullBackOff`, the GHCR package is private: make it public once
(GitHub → Packages → Package settings → Change visibility).

---

## Docker-only quickstart

```bash
make test          # unit tests
make run           # from source on :8000, auto-reload
make docker-run    # the built image on :8000
make observe       # Compose: app + Prometheus (:9090) + Grafana (:3000)
```

The Compose Grafana comes up with the same SLO dashboard already loaded.

---

## AWS track

```
   Internet ──80──▶ ALB (public subnets)
                     │
                     ▼
            ECS Fargate service (private subnets)
              FastAPI agent, rolling deploy with circuit breaker
              task role: bedrock:InvokeModel (scoped)
                     │
          ┌──────────┴──────────┐
          ▼                     ▼
   RDS Postgres (encrypted)   ElastiCache Redis (encrypted)

   Secrets Manager: DB password      CloudWatch SLO alarms → SNS
```

One-time bootstrap: an S3 bucket for Terraform state and a GitHub OIDC role.
Fill in the `REPLACE-ME` values in `infra/envs/*/backend.tf`, add the
`AWS_PLAN_ROLE_ARN` / `AWS_DEPLOY_ROLE_ARN` secrets, and set the repository
variable `AWS_ENABLED=true`. Until then the AWS jobs are skipped and CI stays
green.

```bash
make plan ENV=dev          # see the plan
make plan-policy ENV=dev   # plan + run the policy gate locally
```

Merging to `main` deploys dev (`deploy.yml`); `prod` sits behind a GitHub
Environment approval.

---

## CI/CD: what runs when

| Event | Workflow | What it does |
|---|---|---|
| push or pull request to `main` | `ci.yml` | every check in the table below |
| push a `vX.Y.Z` tag | `release.yml` | image to GHCR, `newTag` commit, GitHub Release |
| change in `k8s/` on `main` | ArgoCD (in the cluster) | pulls and applies it: **pull-based CD**, CI never holds cluster credentials |
| push to `main` or manual run | `deploy.yml` | AWS: OIDC role → ECR → `terraform apply` → ECS → smoke test (only with `AWS_ENABLED`) |

A tag push runs only `release.yml`, not CI, so push the code to `main` and
let CI pass before tagging. The bot's own commit does not trigger new
workflow runs.

### CI checks

| Job | Blocks merge on |
|---|---|
| App lint & tests | ruff findings, failing pytest |
| Image build & Trivy | fixable HIGH/CRITICAL CVEs |
| gitleaks | committed secrets |
| Terraform | `fmt` drift, `validate` errors in all three roots |
| Policy tests | Rego formatting, failing policy unit tests |
| Kubernetes manifests | schema errors (kubeconform), security policy violations |
| Alert rules | invalid PromQL, alert unit tests, invalid Alertmanager config |
| shellcheck | script bugs |
| AWS plan + policy | Terraform policy violations (only with `AWS_ENABLED`) |

Checkov runs in report-only mode because the demo knowingly defers some
hardening (see below); the rules this project enforces are written as code
in `policy/`.

### Policy as code (`policy/`)

- `terraform.rego`: no public S3, no `Action:*` on `Resource:*`, encrypted data
  stores, Environment tag.
- `k8s.rego`: non-root, no privilege escalation, all capabilities dropped,
  pinned image tags, CPU/memory requests and limits, liveness and readiness
  probes.
- `*_test.rego`: unit tests for both (`make policy-test`).

The Kubernetes rules target the failure classes that are common in
hand-written and LLM-generated manifests. The cluster enforces the same
baseline from the other side: the `agentic-gp` namespace runs the
`restricted` Pod Security Standard, so a pod that breaks these rules is
rejected by the API server even if it gets past CI.

---

## SLOs and alerts

**SLO:** 99.5% of `/agent` requests succeed and p95 latency stays under 1 s.

| Alert | Fires when | Severity |
|---|---|---|
| AgentHighErrorRate | > 5% errors for 2 min | critical |
| AgentErrorBudgetBurn | 1 h **and** 5 m error ratio > 14.4 × budget | warning |
| AgentHighLatencyP95 | p95 > 1 s for 2 min | warning |
| AgentAllReplicasDown | no pod scrapeable for 1 min | critical |
| AgentReplicaDown | a pod not scrapeable for 1 min | warning |

The alerts have unit tests (`observability/tests/alert-rules.test.yaml`,
`make alert-test`): promtool replays synthetic healthy, failing, slow and
down traffic and asserts exactly which alerts fire, so a broken threshold
fails CI instead of failing silently in production.

The SLIs are recording rules, computed once and reused by alerts and
dashboards. Alertmanager inhibition keeps it to one page per incident: while
AgentAllReplicasDown fires, the per-pod and SLO warnings are suppressed, and
AgentHighErrorRate suppresses the budget-burn warning it implies. On AWS the
same SLO is expressed as CloudWatch alarms on ALB metrics.

---

## Found while running it

Bugs that only showed up on a real cluster, and what now prevents them:

- **Silent label collision.** The app's metrics first used a label called
  `endpoint`. The Prometheus Operator adds its own `endpoint` target label
  (the scrape port name), so Prometheus renamed the app's label to
  `exported_endpoint`, and every alert and panel filtering on
  `endpoint="/agent"` matched nothing: dashboards said "No data", and alerts
  stayed green during a 30 % error drill. The label is now `handler`; a unit
  test fails if a metric uses a reserved target label, and the alert tests
  feed series with the operator's labels attached.
- **Hijacked CI action.** The `aquasecurity/trivy-action` tags were
  compromised in March 2026 (GHSA-69fq-xp46-6x23). CI now downloads a pinned
  Trivy binary and verifies its SHA-256, and every action is pinned to a
  commit SHA, so a moved tag cannot change what runs.
- **Duplicate panel query IDs.** Two queries with the same refId made the
  latency panel show nothing; each query now has its own ID.

---

## Repository layout

```
app/                    FastAPI service, Dockerfile, tests
k8s/                    kustomize: namespace, deployment, service, PDB,
                        ServiceMonitor, PrometheusRule, dashboard
argocd/                 ArgoCD Application
infra/local-kind/       Terraform for the kind cluster (+ plain kind config)
infra/modules/          AWS: network, ecs-service, data, observability
infra/envs/dev, prod/   AWS environments with S3 remote state
observability/k8s/      Helm values: kube-prometheus-stack, Loki
observability/compose/  Prometheus + Grafana provisioning for Compose
observability/tests/    alert rule unit tests (promtool)
policy/                 Rego policies and their unit tests
scripts/                setup, teardown, status, load, chaos, test-alerts
.github/workflows/      ci.yml, release.yml, deploy.yml
```

---

## Intentionally simplified

These are the next steps, not oversights:

- **AWS:** the ALB is HTTP:80 (production wants ACM + HTTPS and a redirect);
  one NAT gateway (production wants one per AZ); no autoscaling yet; on a
  brand-new environment the ECR repo must exist before the first image push
  (`terraform apply -target=module.service.aws_ecr_repository.this` once).
- **Local:** Loki uses `loki-stack` with filesystem storage and Prometheus
  keeps 6 h of data. Production would use the `grafana/loki` chart with object
  storage, Alloy instead of Promtail, and longer retention. Because that Loki
  is older than Grafana, the "Logs volume" bar in Explore shows a parse error;
  the log lines and dashboard panels are unaffected. Grafana's admin
  password is `admin`.
- **App:** Bedrock calls are mocked (`MOCK_LLM=true`); `/ready` does not yet
  check Postgres/Redis.
- **Next layer:** OpenTelemetry tracing, HPA on request latency, and signing
  images with cosign and verifying signatures at admission.

---

*Stack: Python/FastAPI · Docker · Terraform · kind · Kubernetes · kustomize ·
ArgoCD · Helm · Prometheus · Alertmanager · Grafana · Loki · GitHub Actions ·
GHCR · Conftest/OPA · Trivy · gitleaks · Checkov · kubeconform · AWS (VPC, ECS
Fargate, ALB, ECR, RDS, ElastiCache, Secrets Manager, CloudWatch)*
