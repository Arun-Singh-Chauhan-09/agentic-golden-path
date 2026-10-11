# Kubernetes workload guardrails, run in CI against the rendered manifests:
#   kubectl kustomize k8s > rendered.yaml
#   conftest test --policy policy --namespace k8s rendered.yaml
#
# These are the same failure classes that show up in LLM-generated
# manifests (root containers, missing limits, :latest tags, no probes),
# caught before anything reaches a cluster.

package k8s

import rego.v1

workload_kinds := {"Deployment", "StatefulSet", "DaemonSet", "Job"}

pod_spec := input.spec.template.spec if input.kind in workload_kinds

containers contains c if {
	some c in pod_spec.containers
}

name := sprintf("%s/%s", [input.kind, input.metadata.name])

# --- identity: never run as root ----------------------------------------
deny contains msg if {
	pod_spec
	not pod_spec.securityContext.runAsNonRoot
	msg := sprintf("%s: pod securityContext.runAsNonRoot must be true", [name])
}

deny contains msg if {
	some c in containers
	object.get(c, ["securityContext", "allowPrivilegeEscalation"], true) != false
	msg := sprintf("%s: container %q must set allowPrivilegeEscalation: false", [name, c.name])
}

deny contains msg if {
	some c in containers
	object.get(c, ["securityContext", "privileged"], false) == true
	msg := sprintf("%s: container %q must not be privileged", [name, c.name])
}

deny contains msg if {
	some c in containers
	not "ALL" in object.get(c, ["securityContext", "capabilities", "drop"], [])
	msg := sprintf("%s: container %q must drop ALL capabilities", [name, c.name])
}

# --- supply chain: images must be pinned --------------------------------
deny contains msg if {
	some c in containers
	not contains(c.image, ":")
	msg := sprintf("%s: container %q image %q has no tag", [name, c.name, c.image])
}

deny contains msg if {
	some c in containers
	endswith(c.image, ":latest")
	msg := sprintf("%s: container %q uses :latest; pin a version", [name, c.name])
}

# --- operability: resources and probes ----------------------------------
deny contains msg if {
	some c in containers
	some kind in ["requests", "limits"]
	some res in ["cpu", "memory"]
	not c.resources[kind][res]
	msg := sprintf("%s: container %q is missing resources.%s.%s", [name, c.name, kind, res])
}

deny contains msg if {
	input.kind != "Job"
	some c in containers
	some probe in ["livenessProbe", "readinessProbe"]
	not c[probe]
	msg := sprintf("%s: container %q has no %s", [name, c.name, probe])
}

# --- hardening that is recommended, not blocking ------------------------
warn contains msg if {
	some c in containers
	not c.securityContext.readOnlyRootFilesystem
	msg := sprintf("%s: container %q should use readOnlyRootFilesystem", [name, c.name])
}

warn contains msg if {
	input.kind == "Deployment"
	input.spec.replicas < 2
	msg := sprintf("%s: fewer than 2 replicas means downtime during node failures", [name])
}
