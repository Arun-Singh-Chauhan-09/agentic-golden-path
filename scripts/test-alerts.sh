#!/usr/bin/env bash
# Check and unit-test the alert rules without a cluster.
# Extracts spec.groups from the PrometheusRule (a Kubernetes object) into a
# plain Prometheus rules file, then runs promtool on it. Also checks the
# Alertmanager config embedded in the Helm values with amtool.
#
# Needs: python3 with PyYAML, promtool, amtool (both from the Prometheus /
# Alertmanager release tarballs).
set -euo pipefail
cd "$(dirname "$0")/.."

out=observability/tests/rules.generated.yaml
python3 - k8s/prometheusrule.yaml "$out" <<'EOF'
import sys, yaml
spec = yaml.safe_load(open(sys.argv[1]))["spec"]
yaml.safe_dump(spec, open(sys.argv[2], "w"), sort_keys=False)
EOF

echo "==> promtool check rules"
promtool check rules "$out"

echo "==> promtool test rules"
promtool test rules observability/tests/alert-rules.test.yaml

echo "==> amtool check-config (Alertmanager config from Helm values)"
am=$(mktemp)
python3 - observability/k8s/kube-prometheus-values.yaml "$am" <<'EOF'
import sys, yaml
cfg = yaml.safe_load(open(sys.argv[1]))["alertmanager"]["config"]
yaml.safe_dump(cfg, open(sys.argv[2], "w"), sort_keys=False)
EOF
amtool check-config "$am"
rm -f "$am"
