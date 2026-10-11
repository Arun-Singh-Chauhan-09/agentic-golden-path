# Custom org guardrails, enforced in CI against a Terraform plan.
#
# Usage:
#   terraform -chdir=infra/envs/dev plan -out tf.plan
#   terraform -chdir=infra/envs/dev show -json tf.plan > plan.json
#   conftest test --policy policy --namespace main plan.json
#
# These are intentionally opinionated "paved road" rules: the kind of thing
# Checkov won't know about your org, but that you want to block on.

package main

import rego.v1

# Resources being created or updated in this plan.
changed contains res if {
	some res in input.resource_changes
	some action in res.change.actions
	action in {"create", "update"}
}

# --- Guardrail 1: no public S3 buckets ----------------------------------
deny contains msg if {
	some res in changed
	res.type == "aws_s3_bucket_public_access_block"
	not res.change.after.block_public_acls
	msg := sprintf("S3 bucket %q must block public ACLs", [res.address])
}

deny contains msg if {
	some res in changed
	res.type == "aws_s3_bucket_acl"
	res.change.after.acl in {"public-read", "public-read-write"}
	msg := sprintf("S3 bucket %q has a public ACL (%s)", [res.address, res.change.after.acl])
}

# --- Guardrail 2: no wildcard IAM (Action "*" on Resource "*") ----------
deny contains msg if {
	some res in changed
	res.type in {"aws_iam_role_policy", "aws_iam_policy"}
	doc := json.unmarshal(res.change.after.policy)
	some stmt in to_array(doc.Statement)
	stmt.Effect == "Allow"
	"*" in to_array(stmt.Action)
	"*" in to_array(stmt.Resource)
	msg := sprintf("IAM policy %q grants Action:* on Resource:*; scope it down", [res.address])
}

# --- Guardrail 3: data stores must be encrypted at rest -----------------
deny contains msg if {
	some res in changed
	res.type == "aws_db_instance"
	not res.change.after.storage_encrypted
	msg := sprintf("RDS instance %q must have storage_encrypted = true", [res.address])
}

deny contains msg if {
	some res in changed
	res.type == "aws_elasticache_replication_group"
	not res.change.after.at_rest_encryption_enabled
	msg := sprintf("ElastiCache %q must enable at-rest encryption", [res.address])
}

# --- Guardrail 4: key resources should carry an Environment tag ---------
# Checks tags_all, which includes the provider's default_tags.
warn contains msg if {
	some res in changed
	res.type in taggable
	tags := object.get(res.change.after, "tags_all", object.get(res.change.after, "tags", {}))
	not tags.Environment
	msg := sprintf("%q is missing an Environment tag", [res.address])
}

# --- helpers ------------------------------------------------------------
taggable := {
	"aws_db_instance",
	"aws_ecs_service",
	"aws_lb",
	"aws_ecr_repository",
	"aws_cloudwatch_log_group",
}

to_array(x) := x if is_array(x)

to_array(x) := [x] if not is_array(x)
