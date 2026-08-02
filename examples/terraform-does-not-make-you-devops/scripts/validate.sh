#!/usr/bin/env bash
set -euo pipefail

example_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
terraform_cmd=(terraform)
terragrunt_cmd=(terragrunt)

if command -v mise >/dev/null 2>&1; then
  if terraform_path="$(mise which terraform 2>/dev/null)"; then
    terraform_cmd=("$terraform_path")
  fi

  if terragrunt_path="$(mise which terragrunt 2>/dev/null)"; then
    terragrunt_cmd=("$terragrunt_path")
  fi
fi

"${terraform_cmd[@]}" fmt -check -recursive \
  "$example_root/bootstrap" \
  "$example_root/modules" \
  "$example_root/provisioning-only"

"${terraform_cmd[@]}" -chdir="$example_root/bootstrap" init -backend=false -input=false
"${terraform_cmd[@]}" -chdir="$example_root/bootstrap" validate
"${terraform_cmd[@]}" -chdir="$example_root/bootstrap" test

"${terraform_cmd[@]}" -chdir="$example_root/modules/workload-foundation" init -backend=false -input=false
"${terraform_cmd[@]}" -chdir="$example_root/modules/workload-foundation" validate
"${terraform_cmd[@]}" -chdir="$example_root/modules/workload-foundation" test

"${terraform_cmd[@]}" -chdir="$example_root/provisioning-only" init -backend=false -input=false
"${terraform_cmd[@]}" -chdir="$example_root/provisioning-only" validate
"${terraform_cmd[@]}" -chdir="$example_root/provisioning-only" test

ARM_SUBSCRIPTION_ID="00000000-0000-0000-0000-000000000000" \
TG_STATE_RESOURCE_GROUP="rg-static-validation" \
TG_STATE_STORAGE_ACCOUNT="ststaticvalidation" \
TG_STATE_CONTAINER="tfstate" \
LAB_NAME_PREFIX="tndvalidate" \
LAB_OWNER="static-validation" \
LAB_EXPIRES_ON="2099-12-31" \
"${terragrunt_cmd[@]}" hcl format --check --working-dir "$example_root/platform"

ARM_SUBSCRIPTION_ID="00000000-0000-0000-0000-000000000000" \
TG_STATE_RESOURCE_GROUP="rg-static-validation" \
TG_STATE_STORAGE_ACCOUNT="ststaticvalidation" \
TG_STATE_CONTAINER="tfstate" \
LAB_NAME_PREFIX="tndvalidate" \
LAB_OWNER="static-validation" \
LAB_EXPIRES_ON="2099-12-31" \
"${terragrunt_cmd[@]}" hcl validate --inputs --strict \
  --working-dir "$example_root/platform" \
  --tf-path terraform

PYTHONDONTWRITEBYTECODE=1 \
python3 -m unittest discover -s "$example_root/tests" -p 'test_*.py'

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "$example_root"/scripts/*.sh
else
  printf 'ShellCheck is required for the complete validation path.\n' >&2
  exit 69
fi
