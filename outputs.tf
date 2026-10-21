output "web_acl_arn" {
  description = "ARN of the Regional Web ACL."
  value       = aws_wafv2_web_acl.this.arn
}

output "web_acl_id" {
  description = "ID of the Regional Web ACL."
  value       = aws_wafv2_web_acl.this.id
}

output "web_acl_name" {
  description = "Name of the Regional Web ACL."
  value       = aws_wafv2_web_acl.this.name
}

output "web_acl_association_id" {
  description = "ID of the association between the Web ACL and the existing ALB."
  value       = aws_wafv2_web_acl_association.alb.id
}

output "associated_alb_arn" {
  description = "ALB ARN supplied by the operator and associated with the Web ACL."
  value       = var.alb_arn
}

output "rule_mode" {
  description = "Effective rule mode applied to detection rules and managed rule groups."
  value       = var.rule_mode
}

output "rules" {
  description = "Rule name, priority, and effective action, in evaluation order."
  value = [
    for rule in local.waf_rules : {
      name     = rule.name
      priority = rule.priority
      action   = coalesce(rule.action, rule.override_action)
    }
  ]
}

output "enabled_rules" {
  description = "Rules that exist in this Regional Web ACL."
  value       = sort(var.enabled_rules)
}

output "effective_rule_actions" {
  description = "Action applied to every rule name, after merging rule_mode with rule_actions."
  value       = local.effective_rule_actions
}

output "log_bucket_name" {
  description = "Operator-provided S3 bucket that receives the WAF logs."
  value       = var.log_bucket_name
}

output "firehose_delivery_stream_arn" {
  description = "ARN of the Firehose delivery stream, or null when logging is disabled."
  value       = var.enable_waf_logging ? aws_kinesis_firehose_delivery_stream.waf[0].arn : null
}

output "firehose_iam_role_arn" {
  description = "Role the log bucket policy must allow to write, or null when logging is disabled."
  value       = var.enable_waf_logging ? aws_iam_role.firehose[0].arn : null
}

output "firehose_error_log_group_name" {
  description = "CloudWatch log group receiving Firehose delivery errors, or null when logging is disabled."
  value       = var.enable_waf_logging ? aws_cloudwatch_log_group.firehose[0].name : null
}
