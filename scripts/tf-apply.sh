#!/bin/sh
#
# Applies the exact plan file produced and approved earlier. This script never
# runs `terraform plan`, so no new plan can appear after the approval.
#
# Required environment:
#   AWS_REGION, WAF_SCOPE, TF_STATE_BUCKET, AWS_ROLE_ARN
# Optional:
#   TF_STATE_REGION, TF_STATE_PREFIX, PLAN_FILE, PLAN_CHECKSUM

set -eu

cd "$(dirname "$0")/.."

./scripts/require-env.sh AWS_REGION WAF_SCOPE TF_STATE_BUCKET AWS_ROLE_ARN

plan_file="${PLAN_FILE:-tfplan.bin}"
plan_checksum="${PLAN_CHECKSUM:-tfplan.sha256}"

if [ ! -f "${plan_file}" ]; then
  echo "Missing plan file: ${plan_file}. Refusing to regenerate a plan." >&2
  exit 1
fi

sha256sum -c "${plan_checksum}"

eval "$(./scripts/assume-role.sh)"
./scripts/tf-init.sh

terraform apply -input=false "${plan_file}"
