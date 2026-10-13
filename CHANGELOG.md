# Changelog

All notable changes follow [Keep a Changelog](https://keepachangelog.com/)
and [Semantic Versioning](https://semver.org/). Releases are cut by pushing a
`vX.Y.Z` tag (`make release VERSION=X.Y.Z`); the release workflow builds the
image and moves the GitOps pointer.

## [Unreleased]
### Fixed
- Request metrics now use the label `handler` instead of `endpoint`. The
  Prometheus Operator adds its own `endpoint` target label (the scrape port
  name); on the clash Prometheus renamed the app's label to
  `exported_endpoint`, so every SLO alert and dashboard panel filtering on
  `endpoint="/agent"` silently matched nothing. A unit test now fails if a
  metric uses any reserved target label, and the alert tests include the
  operator's labels so a clash can't hide again.
- `setup.sh` waits for port-forwards before reporting them unreachable;
  `status.sh` works on Python 3.10.

### Security
- Replaced `aquasecurity/trivy-action` with a pinned Trivy 0.69.3 binary whose
  SHA-256 is verified in CI. The action's tags were hijacked in March 2026
  (GHSA-69fq-xp46-6x23) and the old tags were deleted.
- Pinned every GitHub Action to a full commit SHA (with the version as a
  comment), so a moved tag cannot change what runs.
- Pinned runners to `ubuntu-24.04` instead of the moving `ubuntu-latest`.
- Upgraded FastAPI to 0.143.0 so Starlette resolves to a release with the
  2025-2026 security fixes (e.g. CVE-2025-62727, CVE-2026-48710).
- Added Dependabot for actions, pip, the Docker base image and Terraform.

## [0.2.0] - 2026-10-11
### Added
- Local Kubernetes track: kind cluster provisioned by Terraform (`infra/local-kind`),
  one-command `scripts/setup.sh` / `teardown.sh`, all calls pinned to the
  project's own kube context.
- Hardened manifests via kustomize: non-root, read-only root filesystem,
  dropped capabilities, seccomp, liveness + readiness probes, resource
  limits, PodDisruptionBudget, namespace enforcing the `restricted` Pod
  Security Standard.
- GitOps with ArgoCD (auto-sync, prune, self-heal).
- Monitoring: kube-prometheus-stack, ServiceMonitor, SLO recording rules,
  alerts for availability, error rate, multi-window error-budget burn and
  p95 latency; Alertmanager routing by severity with inhibition.
- Logs: Loki + Promtail; the app writes one JSON object per request to stdout.
- Grafana dashboard shipped as code, auto-provisioned in both Kubernetes and
  Docker Compose.
- Chaos drills (`scripts/chaos.sh`): error injection, latency injection, pod
  kill, full outage. Traffic generator (`scripts/load.sh`).
- Tag-driven release workflow: GHCR image with SBOM and provenance, automatic
  GitOps tag bump, GitHub Release notes.
- Kubernetes policy gate (Conftest) and schema validation (kubeconform) in CI;
  unit tests for all Rego policies; shellcheck for scripts.
- App: `FAILURE_RATE` / `EXTRA_LATENCY_MS` chaos knobs, `agent_build_info`
  metric, `GET /` service info, bounded metric label cardinality.

### Changed
- CI runs green without an AWS account: AWS plan/deploy jobs only run when the
  `AWS_ENABLED` repository variable is `true`.
- Checkov reports findings without blocking; the Conftest policy is the
  blocking gate.
- Policies moved to `policy/` and rewritten in Rego v1 syntax.

### Fixed
- Terraform formatting that would have failed `terraform fmt -check` in CI.

## [0.1.0] - 2026-10-02
### Added
- FastAPI mock agent service with health, readiness, agent and metrics endpoints.
- Multi-stage, non-root Docker image with healthcheck.
- AWS track: Terraform modules for VPC, ECS Fargate + ALB, RDS + Redis,
  CloudWatch SLO alarms; dev and prod environments with S3 remote state.
- GitHub Actions CI (tests, Trivy, gitleaks, Checkov, plan + policy) and
  OIDC-based deploy pipeline with ECS circuit-breaker rollback.
