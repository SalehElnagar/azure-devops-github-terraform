#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
subject="$repo_root/scripts/terraform-ci.sh"
failures=0
tests=0

fail() {
  printf 'not ok %d - %s\n' "$tests" "$1"
  failures=$((failures + 1))
}

pass() {
  printf 'ok %d - %s\n' "$tests" "$1"
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  if [[ "$expected" == "$actual" ]]; then
    pass "$message"
  else
    fail "$message (expected $expected, got $actual)"
  fi
}

assert_contains() {
  local file="$1"
  local pattern="$2"
  local message="$3"
  if grep -F -- "$pattern" "$file" >/dev/null; then
    pass "$message"
  else
    fail "$message (missing: $pattern)"
  fi
}

if [[ ! -x "$subject" ]]; then
  printf 'not ok 1 - lifecycle helper exists and is executable\n'
  exit 1
fi

test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT
fake_bin="$test_root/bin"
mkdir -p "$fake_bin"

cat >"$fake_bin/terraform" <<'FAKE'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >>"${FAKE_TERRAFORM_LOG:?}"
case "${1:-}" in
  version)
    if [[ "${2:-}" == "-json" ]]; then
      printf '{"terraform_version":"1.14.7"}\n'
    else
      printf 'Terraform v1.14.7\n'
    fi
    ;;
  plan)
    for arg in "$@"; do
      case "$arg" in
        -out=*) printf 'saved plan\n' >"${arg#-out=}" ;;
      esac
    done
    exit "${FAKE_TERRAFORM_PLAN_EXIT_CODE:-2}"
    ;;
  apply)
    exit "${FAKE_TERRAFORM_APPLY_EXIT_CODE:-0}"
    ;;
esac
FAKE
chmod +x "$fake_bin/terraform"

export PATH="$fake_bin:$PATH"
export FAKE_TERRAFORM_LOG="$test_root/terraform.log"
commit_sha="0123456789abcdef0123456789abcdef01234567"

tests=$((tests + 1))
set +e
"$subject" plan >/dev/null 2>&1
status=$?
set -e
assert_eq 64 "$status" "missing plan arguments return usage status"

plan_file="$test_root/tfplan"
metadata_file="$test_root/metadata.json"
var_file="$test_root/dev.tfvars"
lock_file="$test_root/.terraform.lock.hcl"
printf 'environment = "dev"\n' >"$var_file"
printf 'provider lock\n' >"$lock_file"

tests=$((tests + 1))
FAKE_TERRAFORM_PLAN_EXIT_CODE=2 "$subject" plan \
  --operation apply \
  --var-file "$var_file" \
  --target-resource-group rg-demo-gha \
  --owner platform-team \
  --expires-on 2026-08-07 \
  --stack-name demo-gha \
  --deployed-by "GitHub Actions" \
  --commit-sha "$commit_sha" \
  --plan-file "$plan_file" \
  --metadata-file "$metadata_file" \
  --provider-lock-file "$lock_file"
assert_eq 0 "$?" "changed plan succeeds"

tests=$((tests + 1))
assert_contains "$metadata_file" '"operation": "apply"' "plan metadata records operation"

tests=$((tests + 1))
assert_contains "$FAKE_TERRAFORM_LOG" "-out=$plan_file" "plan uses requested output file"

tests=$((tests + 1))
assert_contains "$FAKE_TERRAFORM_LOG" "-var=target_resource_group_name=rg-demo-gha" "target resource group is explicit"

tests=$((tests + 1))
assert_contains "$FAKE_TERRAFORM_LOG" "-var=owner=platform-team" "resource owner is explicit"

tests=$((tests + 1))
assert_contains "$FAKE_TERRAFORM_LOG" "-var=expires_on=2026-08-07" "resource expiry is explicit"

tests=$((tests + 1))
: >"$FAKE_TERRAFORM_LOG"
FAKE_TERRAFORM_PLAN_EXIT_CODE=2 "$subject" plan \
  --operation destroy \
  --var-file "$var_file" \
  --target-resource-group rg-demo-gha \
  --owner platform-team \
  --expires-on 2026-08-07 \
  --stack-name demo-gha \
  --deployed-by "GitHub Actions" \
  --commit-sha "$commit_sha" \
  --plan-file "$plan_file" \
  --metadata-file "$metadata_file" \
  --provider-lock-file "$lock_file"
assert_contains "$FAKE_TERRAFORM_LOG" "-destroy" "destroy plan adds explicit destroy flag"

tests=$((tests + 1))
: >"$FAKE_TERRAFORM_LOG"
"$subject" apply \
  --plan-file "$plan_file" \
  --metadata-file "$metadata_file" \
  --provider-lock-file "$lock_file" \
  --expected-operation destroy \
  --expected-commit "$commit_sha" \
  --max-plan-age-seconds 86400
assert_contains "$FAKE_TERRAFORM_LOG" "apply -input=false -no-color $plan_file" "verified plan is applied"

tests=$((tests + 1))
set +e
"$subject" apply \
  --plan-file "$plan_file" \
  --metadata-file "$metadata_file" \
  --provider-lock-file "$lock_file" \
  --expected-operation apply \
  --expected-commit "$commit_sha" >/dev/null 2>&1
status=$?
set -e
assert_eq 65 "$status" "operation mismatch is rejected"

tests=$((tests + 1))
set +e
"$subject" apply \
  --plan-file "$plan_file" \
  --metadata-file "$metadata_file" \
  --provider-lock-file "$lock_file" \
  --expected-operation destroy \
  --expected-commit "1123456789abcdef0123456789abcdef01234567" >/dev/null 2>&1
status=$?
set -e
assert_eq 65 "$status" "commit mismatch is rejected"

tests=$((tests + 1))
printf 'tampered lock\n' >>"$lock_file"
set +e
"$subject" apply \
  --plan-file "$plan_file" \
  --metadata-file "$metadata_file" \
  --provider-lock-file "$lock_file" \
  --expected-operation destroy \
  --expected-commit "$commit_sha" >/dev/null 2>&1
status=$?
set -e
assert_eq 65 "$status" "provider lockfile mismatch is rejected"
printf 'provider lock\n' >"$lock_file"

tests=$((tests + 1))
jq '.created_at = "2000-01-01T00:00:00Z"' "$metadata_file" >"$metadata_file.tmp"
mv "$metadata_file.tmp" "$metadata_file"
set +e
"$subject" apply \
  --plan-file "$plan_file" \
  --metadata-file "$metadata_file" \
  --provider-lock-file "$lock_file" \
  --expected-operation destroy \
  --expected-commit "$commit_sha" \
  --max-plan-age-seconds 60 >/dev/null 2>&1
status=$?
set -e
assert_eq 65 "$status" "stale plan is rejected"
jq '.created_at = (now | strftime("%Y-%m-%dT%H:%M:%SZ"))' "$metadata_file" >"$metadata_file.tmp"
mv "$metadata_file.tmp" "$metadata_file"

tests=$((tests + 1))
printf 'tampered\n' >>"$plan_file"
set +e
"$subject" apply \
  --plan-file "$plan_file" \
  --metadata-file "$metadata_file" \
  --provider-lock-file "$lock_file" \
  --expected-operation destroy \
  --expected-commit "$commit_sha" >/dev/null 2>&1
status=$?
set -e
assert_eq 65 "$status" "tampered plan is rejected"

tests=$((tests + 1))
FAKE_TERRAFORM_PLAN_EXIT_CODE=1 "$subject" plan \
  --operation apply \
  --var-file "$var_file" \
  --target-resource-group rg-demo-gha \
  --owner platform-team \
  --expires-on 2026-08-07 \
  --stack-name demo-gha \
  --deployed-by "GitHub Actions" \
  --commit-sha "$commit_sha" \
  --plan-file "$test_root/failing.tfplan" \
  --metadata-file "$test_root/failing.json" \
  --provider-lock-file "$lock_file" >/dev/null 2>&1 && status=0 || status=$?
assert_eq 1 "$status" "Terraform plan failure is preserved"

if ((failures > 0)); then
  printf '%d of %d assertions failed\n' "$failures" "$tests" >&2
  exit 1
fi

printf '1..%d\n' "$tests"
