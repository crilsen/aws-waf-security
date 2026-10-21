# Priority 20 — AWS Managed Rules Known Bad Inputs.
#
# Blocks request patterns that are known to be malicious regardless of the
# application (for example Log4j and Java deserialization probes). Uses
# override_action for the same reason as the Common Rule Set.

locals {
  rule_managed_known_bad_inputs = contains(local.enabled_rule_names, "managed_known_bad_inputs") ? [
    merge(local.rule_defaults, {
      name            = "aws-managed-known-bad-inputs"
      priority        = 20
      override_action = local.managed_override_action_by_name["managed_known_bad_inputs"]
      metric_name     = "${local.name_base}-aws-managed-known-bad-inputs"

      statement = merge(local.statement_defaults, {
        type                    = "managed_rule_group"
        managed_rule_group_name = "AWSManagedRulesKnownBadInputsRuleSet"
        rule_action_overrides   = var.known_bad_inputs_rule_overrides
      })
    }),
  ] : []
}
