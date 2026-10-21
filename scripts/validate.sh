#!/bin/sh
#
# Runs every validation that is available locally and safe to run:
#   - terraform formatting, initialization without a backend, and validation
#   - static checks on .gitlab-ci.yml and Jenkinsfile
#   - shellcheck on the helper scripts
#
# This never plans or applies against AWS: no credentials are used and the
# backend is not initialized.

set -eu

cd "$(dirname "$0")/.."

echo "==> terraform fmt"
terraform fmt -check -recursive -diff

echo "==> terraform init (no backend)"
terraform init -backend=false -input=false -no-color >/dev/null

echo "==> terraform validate"
terraform validate -no-color

echo "==> pipeline configuration checks"
python3 tests/check_pipelines.py

echo "==> shellcheck"
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck scripts/*.sh
else
  echo "shellcheck not installed; skipped"
fi

echo "All local validations passed."
