#!/usr/bin/env bash
# Steady traffic against POST /agent so the dashboards and SLO alerts have
# data. Prints a status-code tally every 50 requests. Ctrl+C to stop.
#
#   scripts/load.sh                     # 5 req/s against the kind cluster
#   RATE=20 scripts/load.sh             # faster
#   URL=http://localhost:8000 scripts/load.sh   # against make run / compose
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
# shellcheck source=scripts/lib.sh
source scripts/lib.sh

URL="${URL:-http://localhost:${APP_PORT}}"
RATE="${RATE:-5}"
PAUSE="$(awk -v r="$RATE" 'BEGIN { printf "%.3f", 1 / r }')"
PROMPTS=("negotiate this quote" "compare supplier offers" "check order confirmation" "extract line items from PDF")

declare -A tally=()
n=0
trap 'echo; echo "sent $n requests"; for c in "${!tally[@]}"; do echo "  HTTP $c: ${tally[$c]}"; done; exit 0' INT TERM

echo "POST $URL/agent at ~${RATE} req/s (Ctrl+C to stop)"
while true; do
  prompt="${PROMPTS[$((RANDOM % ${#PROMPTS[@]}))]}"
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
    -X POST "$URL/agent" -H 'Content-Type: application/json' \
    -d "{\"prompt\":\"$prompt\"}")"
  tally[$code]=$(( ${tally[$code]:-0} + 1 ))
  n=$((n + 1))
  if (( n % 50 == 0 )); then
    line=""
    for c in "${!tally[@]}"; do line+=" ${c}=${tally[$c]}"; done
    echo "  $n requests:$line"
  fi
  sleep "$PAUSE"
done
