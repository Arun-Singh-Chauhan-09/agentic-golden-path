#!/usr/bin/env bash
# Break the service on purpose and watch the platform notice.
# Run scripts/load.sh in another terminal first: alerts need traffic.
#
#   scripts/chaos.sh errors [rate]   fraction of /agent calls return 500 (default 0.3)
#                                    -> AgentHighErrorRate (critical) in ~3 min
#   scripts/chaos.sh latency [ms]    add delay to every /agent call (default 1500)
#                                    -> AgentHighLatencyP95 (warning) in ~3 min
#   scripts/chaos.sh kill-pod        delete one pod -> ReplicaSet replaces it,
#                                    PDB + 2 replicas keep the service up
#   scripts/chaos.sh outage          scale to 0 -> AgentAllReplicasDown (critical)
#   scripts/chaos.sh off             undo everything, re-enable GitOps self-heal
#
# ArgoCD self-heal would revert these changes within seconds (that's its
# job), so chaos pauses it and "off" turns it back on.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=scripts/lib.sh
source scripts/lib.sh

require kubectl
k get namespace "$NS" >/dev/null 2>&1 || die "namespace $NS not found; run scripts/setup.sh first"

mode="${1:-}"
case "$mode" in
  errors)
    rate="${2:-0.3}"
    set_self_heal false
    k -n "$NS" set env deployment/"$APP" FAILURE_RATE="$rate"
    k -n "$NS" rollout status deployment/"$APP" --timeout=120s
    info "FAILURE_RATE=$rate. Watch: Grafana error-ratio panel, http://localhost:${PROM_PORT}/alerts"
    ;;
  latency)
    ms="${2:-1500}"
    set_self_heal false
    k -n "$NS" set env deployment/"$APP" EXTRA_LATENCY_MS="$ms"
    k -n "$NS" rollout status deployment/"$APP" --timeout=120s
    info "EXTRA_LATENCY_MS=$ms. Watch: Grafana latency panel (p95 crosses the 1s line)"
    ;;
  kill-pod)
    pod="$(k -n "$NS" get pods -l app="$APP" -o jsonpath='{.items[0].metadata.name}')"
    k -n "$NS" delete pod "$pod" --wait=false
    info "deleted $pod; watching replacement (Ctrl+C to stop):"
    k -n "$NS" get pods -l app="$APP" -w
    ;;
  outage)
    set_self_heal false
    k -n "$NS" scale deployment/"$APP" --replicas=0
    info "all pods gone. AgentAllReplicasDown fires after ~1 minute"
    ;;
  off)
    k -n "$NS" set env deployment/"$APP" FAILURE_RATE=0 EXTRA_LATENCY_MS=0 >/dev/null
    k -n "$NS" scale deployment/"$APP" --replicas=2 >/dev/null
    set_self_heal true
    k -n "$NS" rollout status deployment/"$APP" --timeout=120s
    info "back to normal. Alerts resolve once the 5m windows are clean again"
    ;;
  *)
    # Print the comment header (everything up to the first non-comment line).
    awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
    exit 1
    ;;
esac
