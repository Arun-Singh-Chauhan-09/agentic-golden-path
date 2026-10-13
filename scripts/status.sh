#!/usr/bin/env bash
# One screen: pods, rollout, ArgoCD sync state, and alerts firing right now.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
# shellcheck source=scripts/lib.sh
source scripts/lib.sh

step "Pods ($NS)"
k -n "$NS" get pods -l app="$APP" -o wide 2>/dev/null || die "cluster or namespace not found; run scripts/setup.sh"

step "Running image"
k -n "$NS" get deployment "$APP" -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'

step "ArgoCD"
if argocd_app_exists; then
  k -n argocd get application "$APP" \
    -o custom-columns='SYNC:.status.sync.status,HEALTH:.status.health.status,REVISION:.status.sync.revision,SELF-HEAL:.spec.syncPolicy.automated.selfHeal'
else
  info "no ArgoCD application (SKIP_ARGOCD=1, or the repo is not pushed yet)"
fi

step "Alerts firing (via Prometheus on localhost:${PROM_PORT})"
if json="$(curl -fsS --max-time 5 "http://localhost:${PROM_PORT}/api/v1/alerts" 2>/dev/null)"; then
  printf '%s' "$json" | python3 -c '
import json, sys
alerts = [a for a in json.load(sys.stdin)["data"]["alerts"]
          if a["labels"].get("alertname") != "Watchdog"]
if not alerts:
    print("    none")
for a in sorted(alerts, key=lambda a: a["state"]):
    labels = a["labels"]
    # %-formatting, not f-strings: works on every Python 3 (Ubuntu 22.04 ships 3.10)
    print("    %-8s %-8s %-28s %s" % (
        a["state"],
        labels.get("severity", "-"),
        labels["alertname"],
        a["annotations"].get("summary", ""),
    ))
'
else
  info "Prometheus not reachable; re-run scripts/setup.sh to restart port-forwards"
fi
