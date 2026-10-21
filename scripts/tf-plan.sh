#!/bin/sh
#
# Produces the plan for one target and stores it as an ephemeral artifact:
#
#   tfplan.bin       binary plan, applied later without replanning
#   tfplan.txt       human-readable rendering for review
#   tfplan.sha256    checksum verified immediately before apply
#
# The WAF policy comes from the reviewed, versioned file for the target:
#   env/regional/<region>.tfvars
#   env/cloudfront/<region>.tfvars
#
# Required environment:
#   AWS_REGION, WAF_SCOPE, TF_LOG_BUCKET, TF_STATE_BUCKET, AWS_ROLE_ARN
#   ALB_ARN is required only when WAF_SCOPE=REGIONAL
# Optional:
#   TF_STATE_REGION, TF_STATE_PREFIX, PLAN_FILE, PLAN_TEXT, PLAN_CHECKSUM

set -eu

cd "$(dirname "$0")/.."

./scripts/require-env.sh AWS_REGION WAF_SCOPE TF_LOG_BUCKET TF_STATE_BUCKET AWS_ROLE_ARN

scope_dir=$(printf '%s' "${WAF_SCOPE}" | tr '[:upper:]' '[:lower:]')
var_file="env/${scope_dir}/${AWS_REGION}.tfvars"

if [ ! -f "${var_file}" ]; then
  echo "Missing WAF policy file: ${var_file}" >&2
  echo "Create it from env/${scope_dir}/ and commit it before planning." >&2
  exit 1
fi

plan_file="${PLAN_FILE:-tfplan.bin}"
plan_text="${PLAN_TEXT:-tfplan.txt}"
plan_checksum="${PLAN_CHECKSUM:-tfplan.sha256}"

# The ALB is only meaningful for the Regional scope. A CLOUDFRONT Web ACL is
# attached through the distribution's web_acl_id by its owner.
set -- \
  -input=false \
  -lock-timeout=5m \
  -out="${plan_file}" \
  -var="aws_region=${AWS_REGION}" \
  -var="waf_scope=${WAF_SCOPE}" \
  -var="log_bucket_name=${TF_LOG_BUCKET}" \
  -var-file="${var_file}"

if [ "${WAF_SCOPE}" = "REGIONAL" ]; then
  ./scripts/require-env.sh ALB_ARN
  set -- "$@" -var="alb_arn=${ALB_ARN}"
fi

eval "$(./scripts/assume-role.sh)"
./scripts/tf-init.sh

terraform plan "$@"
terraform show -no-color "${plan_file}" > "${plan_text}"
sha256sum "${plan_file}" > "${plan_checksum}"

echo "Plan written to ${plan_file}; review ${plan_text}, then approve."
