#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# The version source is resolved from this script's repository root.
# shellcheck disable=SC1091
source "$repo_root/versions.env"

usage() {
  cat >&2 <<'USAGE'
Usage:
  capture-evidence.sh --commit SHA --records-dir PATH
    --scans-file PATH --output PATH
USAGE
}

die() {
  printf 'Error: %s\n' "$1" >&2
  exit 64
}

require_value() {
  [[ $# -ge 2 && -n "$2" ]] || die "$1 requires a value"
}

commit_sha=""
records_dir=""
scans_file=""
output=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --commit)
      require_value "$@"
      commit_sha="$2"
      shift 2
      ;;
    --records-dir)
      require_value "$@"
      records_dir="$2"
      shift 2
      ;;
    --scans-file)
      require_value "$@"
      scans_file="$2"
      shift 2
      ;;
    --output)
      require_value "$@"
      output="$2"
      shift 2
      ;;
    *)
      usage
      die "unknown argument: $1"
      ;;
  esac
done

[[ "$commit_sha" =~ ^[0-9a-f]{40}$ ]] ||
  die "commit must be a 40-character lowercase Git SHA"
[[ -d "$records_dir" ]] || die "records directory does not exist: $records_dir"
[[ -f "$scans_file" ]] || die "scans file does not exist: $scans_file"
[[ -n "$output" ]] || die "output is required"

record_files=("$records_dir"/*.json)
[[ -e "${record_files[0]}" ]] || die "records directory has no JSON records"
records_json="$(jq -s '.' "${record_files[@]}")"

jq -e '
  all(.[];
    ((keys - ["phase", "platform", "public_url", "result"]) | length) == 0 and
    (.platform | IN("github_actions", "azure_pipelines", "system")) and
    (.phase | IN("create", "update", "no_change", "destroy", "cleanup")) and
    .result == "pass" and
    ((.public_url // "") |
      . == "" or
      test("^https://github\\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/actions/runs/[0-9]+$"))
  )
' <<<"$records_json" >/dev/null ||
  die "records contain unexpected fields, values, or URLs"

for platform in github_actions azure_pipelines; do
  for phase in create update no_change destroy; do
    count="$(
      jq \
        --arg platform "$platform" \
        --arg phase "$phase" \
        '[.[] | select(.platform == $platform and .phase == $phase)] | length' \
        <<<"$records_json"
    )"
    [[ "$count" == "1" ]] ||
      die "expected exactly one $platform $phase record"
  done
done

cleanup_count="$(
  jq '[.[] | select(.platform == "system" and .phase == "cleanup")] | length' \
    <<<"$records_json"
)"
[[ "$cleanup_count" == "1" ]] || die "expected exactly one cleanup record"

jq -e '
  type == "array" and length > 0 and
  all(.[];
    ((keys - ["report", "result", "tool", "version"]) | length) == 0 and
    (.tool | type == "string" and length > 0) and
    (.result | IN("pass", "accepted"))
  )
' "$scans_file" >/dev/null || die "security scan records are invalid"

result_for() {
  jq -er \
    --arg platform "$1" \
    --arg phase "$2" \
    '.[] | select(.platform == $platform and .phase == $phase) | .result' \
    <<<"$records_json"
}

output_dir="$(dirname "$output")"
mkdir -p "$output_dir"
output_tmp="${output}.tmp"
trap 'rm -f "$output_tmp"' EXIT

jq -n \
  --arg commit "$commit_sha" \
  --arg validation_date "$(date -u '+%Y-%m-%d')" \
  --arg terraform_version "$TERRAFORM_VERSION" \
  --arg terraform_linux_amd64_sha256 "$TERRAFORM_LINUX_AMD64_SHA256" \
  --arg azurerm_version "$AZURERM_PROVIDER_VERSION" \
  --arg random_version "$RANDOM_PROVIDER_VERSION" \
  --arg azure_cli_version "$AZURE_CLI_VERSION" \
  --arg github_runner_image "$GITHUB_RUNNER_IMAGE" \
  --arg azure_pipelines_image "$AZURE_PIPELINES_IMAGE" \
  --arg action_checkout_sha "$ACTION_CHECKOUT_SHA" \
  --arg action_setup_terraform_sha "$ACTION_SETUP_TERRAFORM_SHA" \
  --arg action_azure_login_sha "$ACTION_AZURE_LOGIN_SHA" \
  --arg action_upload_artifact_sha "$ACTION_UPLOAD_ARTIFACT_SHA" \
  --arg action_download_artifact_sha "$ACTION_DOWNLOAD_ARTIFACT_SHA" \
  --arg gha_create "$(result_for github_actions create)" \
  --arg gha_update "$(result_for github_actions update)" \
  --arg gha_no_change "$(result_for github_actions no_change)" \
  --arg gha_destroy "$(result_for github_actions destroy)" \
  --arg azdo_create "$(result_for azure_pipelines create)" \
  --arg azdo_update "$(result_for azure_pipelines update)" \
  --arg azdo_no_change "$(result_for azure_pipelines no_change)" \
  --arg azdo_destroy "$(result_for azure_pipelines destroy)" \
  --slurpfile scans "$scans_file" \
  '{
    schema_version: 1,
    release: "verified-dual-pipeline",
    commit: $commit,
    validation_date: $validation_date,
    versions: {
      terraform: $terraform_version,
      terraform_linux_amd64_sha256: $terraform_linux_amd64_sha256,
      azurerm: $azurerm_version,
      random: $random_version,
      azure_cli: $azure_cli_version,
      runner_images: {
        github_actions: $github_runner_image,
        azure_pipelines: $azure_pipelines_image
      },
      github_actions: {
        checkout: $action_checkout_sha,
        setup_terraform: $action_setup_terraform_sha,
        azure_login: $action_azure_login_sha,
        upload_artifact: $action_upload_artifact_sha,
        download_artifact: $action_download_artifact_sha
      }
    },
    lifecycle: {
      github_actions: {
        create: $gha_create,
        update: $gha_update,
        no_change: $gha_no_change,
        destroy: $gha_destroy
      },
      azure_pipelines: {
        create: $azdo_create,
        update: $azdo_update,
        no_change: $azdo_no_change,
        destroy: $azdo_destroy
      },
      cleanup: "pass"
    },
    security_scans: $scans[0],
    cleanup_complete: true
  }' >"$output_tmp"

mv "$output_tmp" "$output"
trap - EXIT
printf 'Wrote sanitized release evidence to %s.\n' "$output"
