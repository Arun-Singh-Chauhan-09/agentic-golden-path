#!/usr/bin/env bash
# One command from nothing to a fully observable, GitOps-managed service on a
# local kind cluster:
#
#   cluster -> image -> monitoring -> logs -> app -> GitOps -> access -> verify
#
# Safe to re-run: every step is idempotent (helm upgrade --install, kubectl
# apply), so running it again repairs a half-finished setup.
#
# Options (environment variables):
#   SKIP_ARGOCD=1          deploy with kubectl only, no ArgoCD
#   ARGOCD_VERSION=v2.x.y  pin ArgoCD (default: stable)

set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=scripts/lib.sh
source scripts/lib.sh

SKIP_ARGOCD="${SKIP_ARGOCD:-0}"
ARGOCD_VERSION="${ARGOCD_VERSION:-stable}"
IMAGE_NAME="$(awk '/newName:/ {print $2}' k8s/kustomization.yaml)"
IMAGE_TAG="$(awk '/newTag:/ {print $2}' k8s/kustomization.yaml)"
IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"
REPO_URL="$(awk '/repoURL:/ {print $2}' argocd/application.yaml)"

require docker kind kubectl helm curl
docker info >/dev/null 2>&1 || die "Docker is not running (start Docker Desktop)"

# ---------------------------------------------------------------------------
step "1/8 Cluster '$CLUSTER'"
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  info "already exists, reusing"
  # A cluster paused with 'docker stop' is still listed by kind: start it.
  for node in $(kind get nodes --name "$CLUSTER"); do
    [ "$(docker inspect -f '{{.State.Running}}' "$node")" = "true" ] || { info "starting $node"; docker start "$node" >/dev/null; }
  done
elif command -v terraform >/dev/null 2>&1; then
  info "creating with Terraform (infra/local-kind)"
  terraform -chdir=infra/local-kind init -input=false >/dev/null
  terraform -chdir=infra/local-kind apply -auto-approve -input=false
else
  info "Terraform not found, creating with kind directly"
  kind create cluster --config infra/local-kind/kind-config.yaml
fi
kind export kubeconfig --name "$CLUSTER" >/dev/null # adds context $CTX
k wait --for=condition=Ready nodes --all --timeout=180s >/dev/null
info "context: $CTX"

# ---------------------------------------------------------------------------
step "2/8 Build image $IMAGE and load it into the cluster"
# The tag comes from k8s/kustomization.yaml, the same tag ArgoCD deploys, so
# the first run needs no registry at all.
docker build --build-arg VERSION="$IMAGE_TAG" -t "$IMAGE" ./app
kind load docker-image "$IMAGE" --name "$CLUSTER"

# ---------------------------------------------------------------------------
step "3/8 Monitoring: Prometheus, Alertmanager, Grafana (takes a few minutes)"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo add grafana https://grafana.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update >/dev/null
h upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --values observability/k8s/kube-prometheus-values.yaml \
  --wait --timeout 10m

# ---------------------------------------------------------------------------
step "4/8 Logs: Loki + Promtail"
h upgrade --install loki grafana/loki-stack \
  --namespace monitoring \
  --values observability/k8s/loki-values.yaml \
  --wait --timeout 5m

# ---------------------------------------------------------------------------
step "5/8 App: Deployment, Service, PDB, ServiceMonitor, alerts, dashboard"
# Applied directly first so the app runs even before the repo is on GitHub.
# ArgoCD (next step) then adopts these resources and owns them from git.
k apply -k k8s
k -n "$NS" rollout status deployment/"$APP" --timeout=180s

# ---------------------------------------------------------------------------
if [ "$SKIP_ARGOCD" = "1" ]; then
  step "6/8 ArgoCD skipped (SKIP_ARGOCD=1)"
else
  step "6/8 GitOps: ArgoCD ($ARGOCD_VERSION)"
  k create namespace argocd --dry-run=client -o yaml | k apply -f - >/dev/null
  # --server-side: the ArgoCD CRDs are too large for client-side apply.
  k apply --server-side --force-conflicts -n argocd \
    -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml" >/dev/null
  k -n argocd rollout status deployment/argocd-server --timeout=300s
  if git ls-remote "$REPO_URL" >/dev/null 2>&1; then
    k apply -f argocd/application.yaml
    info "ArgoCD now syncs $REPO_URL (path k8s/) into namespace $NS"
  else
    info "Repo $REPO_URL is not reachable yet, so ArgoCD has nothing to sync."
    info "Push the project to GitHub, then run:"
    info "  kubectl --context $CTX apply -f argocd/application.yaml"
  fi
fi

# ---------------------------------------------------------------------------
step "7/8 Port-forwards (app and Grafana use kind port mappings instead)"
: >"$PF_PIDFILE"
start_pf() { # description local-port namespace service remote-port
  local desc="$1" lport="$2" ns="$3" svc="$4" rport="$5"
  if port_in_use "$lport"; then
    info "$desc: port $lport already in use, skipped (stop the other process first)"
    return
  fi
  k port-forward -n "$ns" "svc/$svc" "$lport:$rport" >/dev/null 2>&1 &
  echo $! >>"$PF_PIDFILE"
  info "$desc -> localhost:$lport (pid $!)"
}
start_pf "Prometheus  " "$PROM_PORT" monitoring monitoring-kube-prometheus-prometheus 9090
start_pf "Alertmanager" "$ALERTMANAGER_PORT" monitoring monitoring-kube-prometheus-alertmanager 9093
if [ "$SKIP_ARGOCD" != "1" ]; then
  start_pf "ArgoCD      " "$ARGOCD_PORT" argocd argocd-server 443
fi

# ---------------------------------------------------------------------------
step "8/8 Verify"
ok=0
for _ in $(seq 1 30); do
  if curl -fsS "http://localhost:${APP_PORT}/health" >/dev/null 2>&1; then ok=1; break; fi
  sleep 2
done
if [ "$ok" = "1" ]; then
  info "app answers on http://localhost:${APP_PORT}/health"
else
  info "app not reachable on localhost:${APP_PORT} yet; check: kubectl --context $CTX -n $NS get pods"
fi
for pair in "$GRAFANA_PORT:Grafana" "$PROM_PORT:Prometheus" "$ALERTMANAGER_PORT:Alertmanager"; do
  if port_in_use "${pair%%:*}"; then
    info "${pair##*:} listening on ${pair%%:*}"
  else
    info "${pair##*:} NOT reachable on ${pair%%:*}"
  fi
done

ARGO_PW="(ArgoCD skipped)"
if [ "$SKIP_ARGOCD" != "1" ]; then
  ARGO_PW="$(k -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo '(not ready yet)')"
fi

cat <<EOF

======================================================================
 Ready. Endpoints:
======================================================================
  App           http://localhost:${APP_PORT}        (/docs for the API UI)
  Grafana       http://localhost:${GRAFANA_PORT}        admin / admin
                -> Dashboards -> "Agentic Golden Path - Service SLO"
  Prometheus    http://localhost:${PROM_PORT}/alerts
  Alertmanager  http://localhost:${ALERTMANAGER_PORT}
  ArgoCD        https://localhost:${ARGOCD_PORT}       admin / ${ARGO_PW}

 Next:
  make k8s-load            steady traffic so the graphs move
  make chaos-errors        inject 30% errors -> AgentHighErrorRate fires
  make chaos-off           recover (ArgoCD restores the git state)
  make k8s-status          pods, ArgoCD sync state, firing alerts
  make k8s-down            delete the cluster and everything in it
======================================================================
EOF
