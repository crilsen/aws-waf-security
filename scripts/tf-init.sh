#!/bin/sh
#
# Initializes Terraform against the operator-provided backend for one target.
#
# One target is a (scope, Region) pair:
#   REGIONAL   + eu-west-1   -> aws-waf-security/regional/eu-west-1/...
#   CLOUDFRONT + us-east-1   -> aws-waf-security/cloudfront/us-east-1/...
#
# Required environment:
#   AWS_REGION       target Region (CLOUDFRONT must be us-east-1)
#   WAF_SCOPE        REGIONAL or CLOUDFRONT
#   TF_STATE_BUCKET  existing bucket that stores Terraform state
#
# Optional environment:
#   TF_STATE_REGION  Region of the state bucket, defaults to AWS_REGION
#   TF_STATE_PREFIX  key prefix, defaults to aws-waf-security

set -eu

cd "$(dirname "$0")/.."

./scripts/require-env.sh AWS_REGION WAF_SCOPE TF_STATE_BUCKET

case "${WAF_SCOPE}" in
  REGIONAL | CLOUDFRONT) ;;
  *)
    echo "WAF_SCOPE must be REGIONAL or CLOUDFRONT, got: ${WAF_SCOPE}" >&2
    exit 1
    ;;
esac

if [ "${WAF_SCOPE}" = "CLOUDFRONT" ] && [ "${AWS_REGION}" != "us-east-1" ]; then
  echo "A CLOUDFRONT Web ACL must be deployed in us-east-1, got: ${AWS_REGION}" >&2
  exit 1
fi

: "${TF_STATE_REGION:=${AWS_REGION}}"
: "${TF_STATE_PREFIX:=aws-waf-security}"

scope_dir=$(printf '%s' "${WAF_SCOPE}" | tr '[:upper:]' '[:lower:]')
state_key="${TF_STATE_PREFIX}/${scope_dir}/${AWS_REGION}/terraform.tfstate"

echo "State: s3://${TF_STATE_BUCKET}/${state_key} (${TF_STATE_REGION})"

terraform init -input=false \
  -backend-config="bucket=${TF_STATE_BUCKET}" \
  -backend-config="key=${state_key}" \
  -backend-config="region=${TF_STATE_REGION}" \
  -backend-config="encrypt=true"
