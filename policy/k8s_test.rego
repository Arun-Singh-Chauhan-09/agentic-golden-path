# Unit tests for the Kubernetes guardrails:  conftest verify --policy policy

package k8s

import rego.v1

good_container := {
	"name": "app",
	"image": "ghcr.io/example/app:1.2.3",
	"securityContext": {
		"allowPrivilegeEscalation": false,
		"readOnlyRootFilesystem": true,
		"capabilities": {"drop": ["ALL"]},
	},
	"resources": {
		"requests": {"cpu": "50m", "memory": "64Mi"},
		"limits": {"cpu": "500m", "memory": "256Mi"},
	},
	"livenessProbe": {"httpGet": {"path": "/health", "port": 8000}},
	"readinessProbe": {"httpGet": {"path": "/ready", "port": 8000}},
}

deployment(container, pod_sc) := {
	"kind": "Deployment",
	"metadata": {"name": "app"},
	"spec": {
		"replicas": 2,
		"template": {"spec": {"securityContext": pod_sc, "containers": [container]}},
	},
}

good_deployment := deployment(good_container, {"runAsNonRoot": true})

test_hardened_deployment_passes if {
	count(deny) == 0 with input as good_deployment
	count(warn) == 0 with input as good_deployment
}

test_root_pod_denied if {
	count(deny) > 0 with input as deployment(good_container, {})
}

test_latest_tag_denied if {
	c := object.union(good_container, {"image": "nginx:latest"})
	count(deny) > 0 with input as deployment(c, {"runAsNonRoot": true})
}

test_untagged_image_denied if {
	c := object.union(good_container, {"image": "nginx"})
	count(deny) > 0 with input as deployment(c, {"runAsNonRoot": true})
}

test_missing_limits_denied if {
	# object.union merges nested objects, so remove the key before replacing it
	c := object.union(object.remove(good_container, ["resources"]), {"resources": {"requests": {"cpu": "50m", "memory": "64Mi"}}})
	count(deny) > 0 with input as deployment(c, {"runAsNonRoot": true})
}

test_missing_probe_denied if {
	c := object.remove(good_container, ["livenessProbe"])
	count(deny) > 0 with input as deployment(c, {"runAsNonRoot": true})
}

test_capabilities_not_dropped_denied if {
	c := object.union(object.remove(good_container, ["securityContext"]), {"securityContext": {"allowPrivilegeEscalation": false}})
	count(deny) > 0 with input as deployment(c, {"runAsNonRoot": true})
}

test_non_workloads_ignored if {
	count(deny) == 0 with input as {"kind": "Service", "metadata": {"name": "svc"}, "spec": {}}
}
