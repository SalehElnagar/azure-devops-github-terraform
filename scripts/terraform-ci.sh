#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage:
  terraform-ci.sh plan --operation apply|destroy --var-file PATH
    --target-resource-group NAME --owner LABEL --expires-on YYYY-MM-DD
    --stack-name NAME --deployed-by LABEL --commit-sha SHA
    --plan-file PATH --metadata-file PATH --provider-lock-file PATH
  terraform-ci.sh apply --plan-file PATH --metadata-file PATH
    --provider-lock-file PATH --expected-operation apply|destroy
    --expected-commit SHA [--max-plan-age-seconds INTEGER]
USAGE
}

die_usage() {
  printf 'Error: %s\n' "$1" >&2
  usage
  exit 64
}

die_integrity() {
  printf 'Integrity error: %s\n' "$1" >&2
  exit 65
}

require_value() {
  if [[ $# -lt 2 || -z "$2" ]]; then
    die_usage "$1 requires a value"
  fi
}

sha256_file() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  else
    printf 'Neither sha256sum nor shasum is available.\n' >&2
    exit 69
  fi
}

validate_commit() {
  if [[ ! "$1" =~ ^[0-9a-fA-F]{40}$ ]]; then
    die_usage "commit SHA must contain exactly 40 hexadecimal characters"
  fi
}

command_name="${1:-}"
[[ -n "$command_name" ]] || die_usage "a command is required"
shift

case "$command_name" in
  plan)
    operation=""
    var_file=""
    target_resource_group=""
    owner=""
    expires_on=""
    stack_name=""
    deployed_by=""
    commit_sha=""
    plan_file=""
    metadata_file=""
    provider_lock_file=""

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --operation)
          require_value "$@"
          operation="$2"
          shift 2
          ;;
        --var-file)
          require_value "$@"
          var_file="$2"
          shift 2
          ;;
        --target-resource-group)
          require_value "$@"
          target_resource_group="$2"
          shift 2
          ;;
        --owner)
          require_value "$@"
          owner="$2"
          shift 2
          ;;
        --expires-on)
          require_value "$@"
          expires_on="$2"
          shift 2
          ;;
        --stack-name)
          require_value "$@"
          stack_name="$2"
          shift 2
          ;;
        --deployed-by)
          require_value "$@"
          deployed_by="$2"
          shift 2
          ;;
        --commit-sha)
          require_value "$@"
          commit_sha="$2"
          shift 2
          ;;
        --plan-file)
          require_value "$@"
          plan_file="$2"
          shift 2
          ;;
        --metadata-file)
          require_value "$@"
          metadata_file="$2"
          shift 2
          ;;
        --provider-lock-file)
          require_value "$@"
          provider_lock_file="$2"
          shift 2
          ;;
        *)
          die_usage "unknown plan argument: $1"
          ;;
      esac
    done

    [[ "$operation" == "apply" || "$operation" == "destroy" ]] ||
      die_usage "operation must be apply or destroy"
    [[ -f "$var_file" ]] || die_usage "var file does not exist: $var_file"
    [[ -n "$target_resource_group" ]] || die_usage "target resource group is required"
    [[ -n "$owner" ]] || die_usage "owner is required"
    [[ "$expires_on" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] ||
      die_usage "expires-on must use YYYY-MM-DD"
    [[ -n "$stack_name" ]] || die_usage "stack name is required"
    [[ -n "$deployed_by" ]] || die_usage "deployed-by is required"
    validate_commit "$commit_sha"
    commit_sha_normalized="$(printf '%s' "$commit_sha" | tr '[:upper:]' '[:lower:]')"
    [[ -n "$plan_file" ]] || die_usage "plan file is required"
    [[ -n "$metadata_file" ]] || die_usage "metadata file is required"
    [[ -f "$provider_lock_file" ]] ||
      die_usage "provider lock file does not exist: $provider_lock_file"

    plan_args=(
      plan
      -input=false
      -no-color
      -lock-timeout=5m
      -detailed-exitcode
      "-out=$plan_file"
      "-var-file=$var_file"
      "-var=target_resource_group_name=$target_resource_group"
      "-var=owner=$owner"
      "-var=expires_on=$expires_on"
      "-var=stack_name=$stack_name"
      "-var=deployed_by=$deployed_by"
      "-var=commit_sha=$commit_sha_normalized"
    )
    if [[ "$operation" == "destroy" ]]; then
      plan_args+=(-destroy)
    fi

    set +e
    terraform "${plan_args[@]}"
    plan_status=$?
    set -e

    case "$plan_status" in
      0)
        plan_result="no-change"
        ;;
      2)
        plan_result="changed"
        ;;
      *)
        printf 'Terraform plan failed with exit code %d.\n' "$plan_status" >&2
        exit "$plan_status"
        ;;
    esac

    [[ -f "$plan_file" ]] || die_integrity "Terraform did not create the saved plan"
    plan_digest="$(sha256_file "$plan_file")"
    lock_digest="$(sha256_file "$provider_lock_file")"
    terraform_version="$(terraform version -json | jq -er '.terraform_version')"
    created_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    metadata_tmp="${metadata_file}.tmp"

    jq -n \
      --arg operation "$operation" \
      --arg commit_sha "$commit_sha_normalized" \
      --arg plan_digest "$plan_digest" \
      --arg provider_lock_digest "$lock_digest" \
      --arg terraform_version "$terraform_version" \
      --arg plan_result "$plan_result" \
      --arg created_at "$created_at" \
      '{
        schema_version: 1,
        operation: $operation,
        commit_sha: $commit_sha,
        plan_sha256: $plan_digest,
        provider_lock_sha256: $provider_lock_digest,
        terraform_version: $terraform_version,
        plan_result: $plan_result,
        created_at: $created_at
      }' >"$metadata_tmp"
    mv "$metadata_tmp" "$metadata_file"
    printf 'Terraform plan succeeded: %s.\n' "$plan_result"
    ;;

  apply)
    plan_file=""
    metadata_file=""
    provider_lock_file=""
    expected_operation=""
    expected_commit=""
    max_plan_age_seconds="86400"

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --plan-file)
          require_value "$@"
          plan_file="$2"
          shift 2
          ;;
        --metadata-file)
          require_value "$@"
          metadata_file="$2"
          shift 2
          ;;
        --provider-lock-file)
          require_value "$@"
          provider_lock_file="$2"
          shift 2
          ;;
        --expected-operation)
          require_value "$@"
          expected_operation="$2"
          shift 2
          ;;
        --expected-commit)
          require_value "$@"
          expected_commit="$2"
          shift 2
          ;;
        --max-plan-age-seconds)
          require_value "$@"
          max_plan_age_seconds="$2"
          shift 2
          ;;
        *)
          die_usage "unknown apply argument: $1"
          ;;
      esac
    done

    [[ -f "$plan_file" ]] || die_integrity "saved plan does not exist"
    [[ -f "$metadata_file" ]] || die_integrity "plan metadata does not exist"
    [[ -f "$provider_lock_file" ]] || die_integrity "provider lock file does not exist"
    [[ "$expected_operation" == "apply" || "$expected_operation" == "destroy" ]] ||
      die_usage "expected operation must be apply or destroy"
    validate_commit "$expected_commit"
    [[ "$max_plan_age_seconds" =~ ^[1-9][0-9]*$ ]] ||
      die_usage "max plan age must be a positive integer"
    expected_commit_normalized="$(printf '%s' "$expected_commit" | tr '[:upper:]' '[:lower:]')"

    metadata_operation="$(jq -er '.operation' "$metadata_file")" ||
      die_integrity "plan metadata has no operation"
    metadata_commit="$(jq -er '.commit_sha' "$metadata_file")" ||
      die_integrity "plan metadata has no commit"
    metadata_digest="$(jq -er '.plan_sha256' "$metadata_file")" ||
      die_integrity "plan metadata has no digest"
    metadata_lock_digest="$(jq -er '.provider_lock_sha256' "$metadata_file")" ||
      die_integrity "plan metadata has no provider lock digest"
    plan_age_seconds="$(
      jq -er '(.created_at | fromdateiso8601) as $created | (now - $created | floor)' \
        "$metadata_file"
    )" || die_integrity "plan metadata has an invalid creation time"

    [[ "$metadata_operation" == "$expected_operation" ]] ||
      die_integrity "operation does not match reviewed plan"
    [[ "$metadata_commit" == "$expected_commit_normalized" ]] ||
      die_integrity "commit does not match reviewed plan"
    [[ "$metadata_digest" == "$(sha256_file "$plan_file")" ]] ||
      die_integrity "saved plan digest does not match metadata"
    [[ "$metadata_lock_digest" == "$(sha256_file "$provider_lock_file")" ]] ||
      die_integrity "provider lock digest does not match metadata"
    ((plan_age_seconds >= 0 && plan_age_seconds <= max_plan_age_seconds)) ||
      die_integrity "saved plan is stale or has a future timestamp"

    terraform apply -input=false -no-color "$plan_file"
    ;;

  *)
    die_usage "unknown command: $command_name"
    ;;
esac
