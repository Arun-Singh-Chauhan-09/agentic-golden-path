#!/usr/bin/env bash
# Shared settings and helpers, sourced by the other scripts.
#
# Every kubectl/helm call goes through k()/h(), which pin the kube context to
# this project's cluster. Other clusters in your kubeconfig (for example a
# thesis cluster) are never touched, whatever your current context is.

# shellcheck disable=SC2034  # used by the scripts that source this file
CLUSTER="${CLUSTER:-agentic-gp}"
CTX="kind-${CLUSTER}"
NS="agentic-gp"
APP="agentic-gp"

APP_PORT=8090        # kind NodePort mapping (infra/local-kind)
GRAFANA_PORT=3030    # kind NodePort mapping
PROM_PORT=9090       # port-forward
ALERTMANAGER_PORT=9093
ARGOCD_PORT=8443

PF_PIDFILE="${TMPDIR:-/tmp}/agentic-gp-portforwards.pids"

k() { kubectl --context "$CTX" "$@"; }
h() { helm --kube-context "$CTX" "$@"; }

step() { printf '\n==> %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

require() {
  local bin
  for bin in "$@"; do
    command -v "$bin" >/dev/null 2>&1 || die "'$bin' is not installed (see README: prerequisites)"
  done
}

port_in_use() { (echo >"/dev/tcp/127.0.0.1/$1") >/dev/null 2>&1; }

argocd_app_exists() { k -n argocd get application "$APP" >/dev/null 2>&1; }

set_self_heal() { # true|false
  argocd_app_exists || return 0
  k -n argocd patch application "$APP" --type merge \
    -p "{\"spec\":{\"syncPolicy\":{\"automated\":{\"prune\":true,\"selfHeal\":$1}}}}" >/dev/null
  info "ArgoCD self-heal: $1"
}
