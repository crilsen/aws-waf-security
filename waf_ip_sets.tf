# Optional IP sets backing the allow list and deny list rules.
#
# Only IPv4 is supported: an aws_wafv2_ip_set has a single ip_address_version,
# and the MVP keeps one set per list. IPv6 support would require a second set
# per list and an OR statement; it is listed as a limitation in the README.

resource "aws_wafv2_ip_set" "allow" {
  count = length(var.ip_allow_list) > 0 ? 1 : 0

  name               = "${local.name_base}-allow"
  description        = "Operator-provided allow list for ${local.name_base}-web-acl."
  scope              = var.waf_scope
  ip_address_version = "IPV4"
  addresses          = var.ip_allow_list

  tags = local.tags
}

resource "aws_wafv2_ip_set" "deny" {
  count = length(var.ip_deny_list) > 0 ? 1 : 0

  name               = "${local.name_base}-deny"
  description        = "Operator-provided deny list for ${local.name_base}-web-acl."
  scope              = var.waf_scope
  ip_address_version = "IPV4"
  addresses          = var.ip_deny_list

  tags = local.tags
}
