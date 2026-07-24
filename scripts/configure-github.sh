#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage:
  configure-github.sh oidc-subject --repo OWNER/REPOSITORY
  configure-github.sh configure --repo OWNER/REPOSITORY
    --bootstrap-output PATH [--reviewer LOGIN]
USAGE
}

die() {
  printf 'Error: %s\n' "$1" >&2
  exit 64
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command is unavailable: $1"
}

require_value() {
  [[ $# -ge 2 && -n "$2" ]] || die "$1 requires a value"
}

repo=""
bootstrap_output=""
reviewer=""
command_name="${1:-}"
[[ -n "$command_name" ]] || {
  usage
  exit 64
}
shift

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      require_value "$@"
      repo="$2"
      shift 2
      ;;
    --bootstrap-output)
      require_value "$@"
      bootstrap_output="$2"
      shift 2
      ;;
    --reviewer)
      require_value "$@"
      reviewer="$2"
      shift 2
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

require_command gh
require_command jq
require_command az
[[ "$repo" =~ ^[^/]+/[^/]+$ ]] || die "repo must use OWNER/REPOSITORY"
gh repo view "$repo" --json id >/dev/null

case "$command_name" in
  oidc-subject)
    [[ -z "$bootstrap_output" && -z "$reviewer" ]] ||
      die "oidc-subject accepts only --repo"

    gh api \
      --method PUT \
      -H "X-GitHub-Api-Version: 2026-03-10" \
      "repos/$repo/actions/oidc/customization/sub" \
      -F use_default=true \
      -F use_immutable_subject=true >/dev/null

    repo_json="$(gh api -H "X-GitHub-Api-Version: 2026-03-10" "repos/$repo")"
    owner_login="$(jq -er '.owner.login' <<<"$repo_json")"
    owner_id="$(jq -er '.owner.id' <<<"$repo_json")"
    repo_name="$(jq -er '.name' <<<"$repo_json")"
    repo_id="$(jq -er '.id' <<<"$repo_json")"
    printf 'repo:%s@%s/%s@%s\n' "$owner_login" "$owner_id" "$repo_name" "$repo_id"
    ;;

  configure)
    [[ -f "$bootstrap_output" ]] ||
      die "bootstrap output does not exist: $bootstrap_output"
    [[ -n "$reviewer" ]] || reviewer="${repo%%/*}"

    subscription_id="$(az account show --query id -o tsv)"
    tenant_id="$(az account show --query tenantId -o tsv)"
    reviewer_id="$(gh api -H "X-GitHub-Api-Version: 2026-03-10" "users/$reviewer" --jq .id)"

    state_resource_group="$(jq -er '.state.value.resource_group_name' "$bootstrap_output")"
    state_storage_account="$(jq -er '.state.value.storage_account_name' "$bootstrap_output")"
    gha_state_container="$(jq -er '.state.value.containers.github_actions' "$bootstrap_output")"
    gha_target_resource_group="$(jq -er '.target_resource_groups.value.github_actions' "$bootstrap_output")"
    gha_plan_client_id="$(jq -er '.identity_client_ids.value.github_plan' "$bootstrap_output")"
    gha_apply_client_id="$(jq -er '.identity_client_ids.value.github_apply' "$bootstrap_output")"
    owner="$(jq -er '.deployment.value.owner' "$bootstrap_output")"
    expires_on="$(jq -er '.deployment.value.expires_on' "$bootstrap_output")"

    set_variable() {
      gh variable set "$1" --repo "$repo" --body "$2"
    }

    set_variable AZURE_SUBSCRIPTION_ID "$subscription_id"
    set_variable AZURE_TENANT_ID "$tenant_id"
    set_variable AZURE_GITHUB_PLAN_CLIENT_ID "$gha_plan_client_id"
    set_variable AZURE_GITHUB_APPLY_CLIENT_ID "$gha_apply_client_id"
    set_variable STATE_RESOURCE_GROUP "$state_resource_group"
    set_variable STATE_STORAGE_ACCOUNT "$state_storage_account"
    set_variable GHA_STATE_CONTAINER "$gha_state_container"
    set_variable GHA_TARGET_RESOURCE_GROUP "$gha_target_resource_group"
    set_variable RESOURCE_OWNER "$owner"
    set_variable EXPIRES_ON "$expires_on"

    configure_environment() {
      local environment_name="$1"
      local payload
      payload="$(mktemp)"
      jq -n \
        --argjson reviewer_id "$reviewer_id" \
        '{
          wait_timer: 0,
          prevent_self_review: false,
          reviewers: [{type: "User", id: $reviewer_id}],
          deployment_branch_policy: {
            protected_branches: false,
            custom_branch_policies: true
          }
        }' >"$payload"
      gh api \
        --method PUT \
        -H "X-GitHub-Api-Version: 2026-03-10" \
        "repos/$repo/environments/$environment_name" \
        --input "$payload" >/dev/null
      rm -f "$payload"

      if ! gh api \
        -H "X-GitHub-Api-Version: 2026-03-10" \
        "repos/$repo/environments/$environment_name/deployment-branch-policies" \
        --jq '.branch_policies[].name' | grep -Fx main >/dev/null; then
        gh api \
          --method POST \
          -H "X-GitHub-Api-Version: 2026-03-10" \
          "repos/$repo/environments/$environment_name/deployment-branch-policies" \
          -f name=main \
          -f type=branch >/dev/null
      fi
    }

    configure_environment dev
    configure_environment dev-destroy

    gh api \
      --method PUT \
      -H "X-GitHub-Api-Version: 2026-03-10" \
      "repos/$repo/actions/permissions/workflow" \
      -f default_workflow_permissions=read \
      -F can_approve_pull_request_reviews=false >/dev/null

    printf 'Configured GitHub variables and protected environments for %s.\n' "$repo"
    ;;

  *)
    usage
    exit 64
    ;;
esac
