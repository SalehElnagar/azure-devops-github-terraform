#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
subject="$repo_root/scripts/capture-evidence.sh"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT
records="$test_root/records"
mkdir -p "$records"

for platform in github_actions azure_pipelines; do
  for phase in create update no_change destroy; do
    jq -n \
      --arg platform "$platform" \
      --arg phase "$phase" \
      '{platform: $platform, phase: $phase, result: "pass"}' \
      >"$records/$platform-$phase.json"
  done
done

jq -n '{platform: "system", phase: "cleanup", result: "pass"}' \
  >"$records/system-cleanup.json"
jq -n '[{tool: "gitleaks", version: "8.30.0", result: "pass"}]' \
  >"$test_root/scans.json"

output="$test_root/manifest.json"
"$subject" \
  --commit 0123456789abcdef0123456789abcdef01234567 \
  --records-dir "$records" \
  --scans-file "$test_root/scans.json" \
  --output "$output"

jq -e '
  .cleanup_complete == true and
  .lifecycle.github_actions.no_change == "pass" and
  .lifecycle.azure_pipelines.destroy == "pass" and
  .security_scans[0].tool == "gitleaks"
' "$output" >/dev/null

printf 'ok 1 - sanitized lifecycle manifest is generated\n'

jq -n \
  '{platform: "github_actions", phase: "create", result: "pass",
    tenant_id: "must-not-be-published"}' \
  >"$records/github_actions-create.json"

if "$subject" \
  --commit 0123456789abcdef0123456789abcdef01234567 \
  --records-dir "$records" \
  --scans-file "$test_root/scans.json" \
  --output "$output" >/dev/null 2>&1; then
  printf 'not ok 2 - unexpected raw fields are rejected\n'
  exit 1
fi

printf 'ok 2 - unexpected raw fields are rejected\n'
printf '1..2\n'
