# WAF policy for the global (CloudFront) scope.
#
# A CLOUDFRONT Web ACL is global but must be created in us-east-1, which is why
# this file lives under the us-east-1 name. It has no ALB association: the
# distribution owner attaches it with web_acl_id = <web_acl_arn output>.
#
# This file is versioned on purpose and must never contain secrets. The log
# bucket and the state bucket are supplied by the pipeline.

waf_scope = "CLOUDFRONT"

rule_mode = "COUNT"

enabled_rules = [
  "ip_allowlist",
  "ip_denylist",
  "managed_common",
  "managed_known_bad_inputs",
  "geo",
  "rate_limit",
]

# CloudFront sees the viewer IP directly, so the rate limit can be tighter than
# the ALB case where many viewers share a corporate egress address.
# Promote only after review:
#   rule_actions = { rate_limit = "BLOCK" }
rule_actions = {}

rate_limit                       = 5000
rate_limit_evaluation_window_sec = 300

ip_allow_list            = []
ip_deny_list             = []
geo_restricted_countries = ["KP"]

common_rule_set_rule_overrides  = {}
known_bad_inputs_rule_overrides = {}
