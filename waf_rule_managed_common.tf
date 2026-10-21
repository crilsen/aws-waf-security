# Priority 10 — AWS Managed Rules Common Rule Set.
#
# The managed rule group decides the action for each rule inside it, so this
# rule uses `override_action` instead of `action`: `none` keeps the group's
# verdicts (BLOCK mode) and `count` overrides them all to COUNT.
#
# False positives are tuned with rule_action_override entries, one per rule,
# through var.common_rule_set_rule_overrides.

locals {
  rule_managed_common = contains(local.enabled_rule_names, "managed_common") ? [
    merge(local.rule_defaults, {
      name            = "aws-managed-common"
      priority        = 10
      override_action = local.managed_override_action_by_name["managed_common"]
      metric_name     = "${var.name_prefix}-aws-managed-common"

      statement = merge(local.statement_defaults, {
        type                    = "managed_rule_group"
        managed_rule_group_name = "AWSManagedRulesCommonRuleSet"
        rule_action_overrides   = var.common_rule_set_rule_overrides
      })
    }),
  ] : []
}
