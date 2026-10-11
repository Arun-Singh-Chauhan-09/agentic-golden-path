# Unit tests for the Terraform guardrails. Run with:
#   conftest verify --policy policy

package main

import rego.v1

wildcard_policy := json.marshal({"Statement": [{"Effect": "Allow", "Action": "*", "Resource": "*"}]})

scoped_policy := json.marshal({"Statement": [{
	"Effect": "Allow",
	"Action": ["bedrock:InvokeModel"],
	"Resource": ["arn:aws:bedrock:eu-central-1::foundation-model/x"],
}]})

plan_with(res) := {"resource_changes": [res]}

test_wildcard_iam_denied if {
	count(deny) > 0 with input as plan_with({
		"address": "aws_iam_role_policy.bad",
		"type": "aws_iam_role_policy",
		"change": {"actions": ["create"], "after": {"policy": wildcard_policy}},
	})
}

test_scoped_iam_allowed if {
	count(deny) == 0 with input as plan_with({
		"address": "aws_iam_role_policy.good",
		"type": "aws_iam_role_policy",
		"change": {"actions": ["create"], "after": {"policy": scoped_policy}},
	})
}

test_unencrypted_rds_denied if {
	count(deny) > 0 with input as plan_with({
		"address": "aws_db_instance.db",
		"type": "aws_db_instance",
		"change": {"actions": ["create"], "after": {"storage_encrypted": false}},
	})
}

test_public_bucket_acl_denied if {
	count(deny) > 0 with input as plan_with({
		"address": "aws_s3_bucket_acl.site",
		"type": "aws_s3_bucket_acl",
		"change": {"actions": ["update"], "after": {"acl": "public-read"}},
	})
}

test_deleted_resources_ignored if {
	count(deny) == 0 with input as plan_with({
		"address": "aws_db_instance.old",
		"type": "aws_db_instance",
		"change": {"actions": ["delete"], "after": null},
	})
}

test_missing_env_tag_warns if {
	count(warn) > 0 with input as plan_with({
		"address": "aws_lb.this",
		"type": "aws_lb",
		"change": {"actions": ["create"], "after": {"tags_all": {"Project": "x"}}},
	})
}
