#!/bin/sh
#
# Fails fast when a required environment variable is missing or empty, so a
# pipeline stops with a clear message instead of planning against an empty ALB
# ARN or an empty state bucket.
#
# Usage:
#   ./scripts/require-env.sh AWS_REGION AWS_ROLE_ARN TF_STATE_BUCKET

set -eu

if [ "$#" -eq 0 ]; then
  echo "Usage: $0 VARIABLE [VARIABLE...]" >&2
  exit 2
fi

missing=0

for name in "$@"; do
  if [ -z "$(printenv "${name}" 2>/dev/null || true)" ]; then
    echo "Missing required environment variable: ${name}" >&2
    missing=1
  fi
done

if [ "${missing}" -ne 0 ]; then
  exit 1
fi
