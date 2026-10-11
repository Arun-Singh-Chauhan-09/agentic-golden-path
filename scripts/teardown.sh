#!/usr/bin/env bash
# Remove everything setup.sh created: port-forwards and the kind cluster.
# Only this project's cluster is deleted; other kind clusters are untouched.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
# shellcheck source=scripts/lib.sh
source scripts/lib.sh

step "1/2 Stopping port-forwards"
if [ -f "$PF_PIDFILE" ]; then
  while read -r pid; do
    [ -n "$pid" ] && kill "$pid" >/dev/null 2>&1 && info "stopped pid $pid"
  done <"$PF_PIDFILE"
  rm -f "$PF_PIDFILE"
fi
# Fallback for a stale pid file. Matches only forwards for THIS cluster.
pkill -f "kubectl --context $CTX port-forward" >/dev/null 2>&1 || true

step "2/2 Deleting cluster '$CLUSTER'"
if [ -f infra/local-kind/terraform.tfstate ] && command -v terraform >/dev/null 2>&1; then
  terraform -chdir=infra/local-kind destroy -auto-approve -input=false
elif kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  kind delete cluster --name "$CLUSTER"
else
  info "no cluster named '$CLUSTER', nothing to delete"
fi

echo
echo "Done. Remaining kind clusters: $(kind get clusters 2>/dev/null | tr '\n' ' ')"
