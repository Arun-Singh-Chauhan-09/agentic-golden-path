# Changelog

All notable changes follow [Keep a Changelog](https://keepachangelog.com/)
and [Semantic Versioning](https://semver.org/). Releases are cut by pushing a
`vX.Y.Z` tag (`make release VERSION=X.Y.Z`); the release workflow builds the
image and moves the GitOps pointer.

## [Unreleased]

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
