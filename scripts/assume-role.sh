#!/bin/sh
#
# Prints shell export statements for temporary AWS credentials obtained from
# STS. Nothing is written to disk and no credential value is printed.
#
# Usage (the caller evaluates the output, so credentials stay in memory):
#
#   eval "$(./scripts/assume-role.sh)"
#
# Two modes, chosen automatically:
#
#   web identity (GitLab CI OIDC)  AWS_ID_TOKEN must be set
#   role assumption (Jenkins)      ambient credentials from the agent profile
#
# Required environment:
#   AWS_ROLE_ARN   IAM role to assume
#   AWS_REGION     Region used for the STS call
#
# Optional environment:
#   AWS_ID_TOKEN           OIDC token; when set, web-identity federation is used
#   AWS_ROLE_SESSION_NAME  defaults to a timestamped name
#   AWS_ROLE_EXTERNAL_ID   external ID required by the role's trust policy
#   AWS_SESSION_DURATION   seconds, 900-43200, defaults to 3600
#
# Never enable `set -x` around this script: it would print credentials.

set -eu

: "${AWS_ROLE_ARN:?AWS_ROLE_ARN must be set}"
: "${AWS_REGION:?AWS_REGION must be set}"

session_name="${AWS_ROLE_SESSION_NAME:-terraform-$(date -u +%Y%m%dT%H%M%SZ)}"
duration="${AWS_SESSION_DURATION:-3600}"

if [ "${duration}" -lt 900 ] || [ "${duration}" -gt 43200 ]; then
  echo "AWS_SESSION_DURATION must be between 900 and 43200 seconds." >&2
  exit 1
fi

# GitHub Actions OIDC: exchange the runner's request token for an STS audience
# token when the workflow grants `id-token: write`.
if [ -z "${AWS_ID_TOKEN:-}" ] && [ -n "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ]; then
  if [ -z "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:-}" ]; then
    echo "ACTIONS_ID_TOKEN_REQUEST_URL is set but ACTIONS_ID_TOKEN_REQUEST_TOKEN is not." >&2
    exit 1
  fi

  AWS_ID_TOKEN=$(curl -sS -f \
    -H "Authorization: bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" \
    "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=sts.amazonaws.com" | jq -r '.value')

  if [ -z "${AWS_ID_TOKEN}" ] || [ "${AWS_ID_TOKEN}" = "null" ]; then
    echo "Failed to obtain a GitHub OIDC token for STS." >&2
    exit 1
  fi

  export AWS_ID_TOKEN
fi

if [ -n "${AWS_ID_TOKEN:-}" ]; then
  set -- assume-role-with-web-identity \
    --role-arn "${AWS_ROLE_ARN}" \
    --role-session-name "${session_name}" \
    --duration-seconds "${duration}" \
    --web-identity-token "${AWS_ID_TOKEN}"
else
  set -- assume-role \
    --role-arn "${AWS_ROLE_ARN}" \
    --role-session-name "${session_name}" \
    --duration-seconds "${duration}"
fi

if [ -n "${AWS_ROLE_EXTERNAL_ID:-}" ]; then
  set -- "$@" --external-id "${AWS_ROLE_EXTERNAL_ID}"
fi

credentials=$(aws sts "$@" \
  --region "${AWS_REGION}" \
  --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
  --output text)

access_key_id=$(printf '%s' "${credentials}" | cut -f1)
secret_access_key=$(printf '%s' "${credentials}" | cut -f2)
session_token=$(printf '%s' "${credentials}" | cut -f3)

printf 'export AWS_ACCESS_KEY_ID=%s\n' "${access_key_id}"
printf 'export AWS_SECRET_ACCESS_KEY=%s\n' "${secret_access_key}"
printf 'export AWS_SESSION_TOKEN=%s\n' "${session_token}"
printf 'export AWS_DEFAULT_REGION=%s\n' "${AWS_REGION}"
printf 'export AWS_REGION=%s\n' "${AWS_REGION}"
