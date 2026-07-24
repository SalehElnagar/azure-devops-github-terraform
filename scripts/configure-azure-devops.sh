#!/usr/bin/env bash
set -euo pipefail

readonly azure_devops_resource="499b84ac-1321-427f-aa17-267ca6975798"

usage() {
  cat >&2 <<'USAGE'
Usage:
  configure-azure-devops.sh --organization https://dev.azure.com/ORG
    --project PROJECT --repo OWNER/REPOSITORY --bootstrap-output PATH
    [--pipeline-name NAME] [--github-service-connection NAME]
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

organization=""
project=""
repo=""
bootstrap_output=""
pipeline_name="dual-pipeline-terraform"
github_connection_name="SalehElnagar"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --organization)
      require_value "$@"
      organization="${2%/}"
      shift 2
      ;;
    --project)
      require_value "$@"
      project="$2"
      shift 2
      ;;
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
    --pipeline-name)
      require_value "$@"
      pipeline_name="$2"
      shift 2
      ;;
    --github-service-connection)
      require_value "$@"
      github_connection_name="$2"
      shift 2
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

require_command az
require_command jq
[[ "$organization" =~ ^https://dev\.azure\.com/[^/]+$ ]] ||
  die "organization must use https://dev.azure.com/ORG"
[[ -n "$project" ]] || die "project is required"
[[ "$repo" =~ ^[^/]+/[^/]+$ ]] || die "repo must use OWNER/REPOSITORY"
[[ -f "$bootstrap_output" ]] ||
  die "bootstrap output does not exist: $bootstrap_output"

project_path="$(jq -rn --arg value "$project" '$value | @uri')"
api_root="$organization/$project_path/_apis"

devops_rest() {
  az rest --resource "$azure_devops_resource" "$@"
}

account_json="$(az account show -o json)"
subscription_id="$(jq -er '.id' <<<"$account_json")"
subscription_name="$(jq -er '.name' <<<"$account_json")"
tenant_id="$(jq -er '.tenantId' <<<"$account_json")"
approval_user="$(jq -er '.user.name' <<<"$account_json")"
project_json="$(devops_rest --method get --url "$organization/_apis/projects/$project_path?api-version=7.1" -o json)"
project_id="$(jq -er '.id' <<<"$project_json")"

state_resource_group="$(jq -er '.state.value.resource_group_name' "$bootstrap_output")"
state_storage_account="$(jq -er '.state.value.storage_account_name' "$bootstrap_output")"
azdo_state_container="$(jq -er '.state.value.containers.azure_pipelines' "$bootstrap_output")"
azdo_target_resource_group="$(jq -er '.target_resource_groups.value.azure_pipelines' "$bootstrap_output")"
identity_resource_group="$(jq -er '.identity_resource_group_name.value' "$bootstrap_output")"
owner="$(jq -er '.deployment.value.owner' "$bootstrap_output")"
expires_on="$(jq -er '.deployment.value.expires_on' "$bootstrap_output")"

temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

endpoints_json="$temp_dir/endpoints.json"
devops_rest \
  --method get \
  --url "$api_root/serviceendpoint/endpoints?api-version=7.2-preview.4" \
  -o json >"$endpoints_json"

create_service_connection() {
  local endpoint_name="$1"
  local identity_key="$2"
  local identity_client_id
  local identity_name
  local endpoint_json
  local endpoint_id
  local issuer
  local subject
  local payload

  identity_client_id="$(jq -er --arg key "$identity_key" '.identity_client_ids.value[$key]' "$bootstrap_output")"
  identity_name="$(jq -er --arg key "$identity_key" '.identity_names.value[$key]' "$bootstrap_output")"
  endpoint_json="$(jq -c --arg name "$endpoint_name" '[.value[] | select(.name == $name)][0] // empty' "$endpoints_json")"

  if [[ -z "$endpoint_json" ]]; then
    payload="$temp_dir/$endpoint_name.json"
    jq -n \
      --arg subscription_id "$subscription_id" \
      --arg subscription_name "$subscription_name" \
      --arg tenant_id "$tenant_id" \
      --arg client_id "$identity_client_id" \
      --arg endpoint_name "$endpoint_name" \
      --arg project_id "$project_id" \
      --arg project_name "$project" \
      '{
        data: {
          subscriptionId: $subscription_id,
          subscriptionName: $subscription_name,
          environment: "AzureCloud",
          scopeLevel: "Subscription",
          creationMode: "Manual"
        },
        name: $endpoint_name,
        type: "AzureRM",
        url: "https://management.azure.com/",
        authorization: {
          parameters: {
            tenantid: $tenant_id,
            serviceprincipalid: $client_id
          },
          scheme: "WorkloadIdentityFederation"
        },
        isShared: false,
        isReady: true,
        serviceEndpointProjectReferences: [{
          projectReference: {id: $project_id, name: $project_name},
          name: $endpoint_name
        }]
      }' >"$payload"
    endpoint_json="$(
      devops_rest \
        --method post \
        --url "$api_root/serviceendpoint/endpoints?api-version=7.2-preview.4" \
        --headers Content-Type=application/json \
        --body "@$payload" \
        -o json
    )"
  fi

  endpoint_id="$(jq -er '.id' <<<"$endpoint_json")"
  issuer="$(jq -er '.authorization.parameters.workloadIdentityFederationIssuer' <<<"$endpoint_json")"
  subject="$(jq -er '.authorization.parameters.workloadIdentityFederationSubject' <<<"$endpoint_json")"
  [[ "$issuer" == "https://login.microsoftonline.com/$tenant_id/v2.0" ]] ||
    die "$endpoint_name did not return the Microsoft Entra issuer"

  if existing_fic="$(
    az identity federated-credential show \
      --resource-group "$identity_resource_group" \
      --identity-name "$identity_name" \
      --name "$endpoint_name" \
      -o json 2>/dev/null
  )"; then
    [[ "$(jq -er '.issuer' <<<"$existing_fic")" == "$issuer" ]] ||
      die "$endpoint_name has an unexpected federated issuer"
    [[ "$(jq -er '.subject' <<<"$existing_fic")" == "$subject" ]] ||
      die "$endpoint_name has an unexpected federated subject"
  else
    az identity federated-credential create \
      --resource-group "$identity_resource_group" \
      --identity-name "$identity_name" \
      --name "$endpoint_name" \
      --issuer "$issuer" \
      --subject "$subject" \
      --audiences api://AzureADTokenExchange \
      -o none
  fi

  printf '%s\n' "$endpoint_id"
}

plan_endpoint_id="$(create_service_connection dual-pipeline-azdo-plan azure_pipelines_plan)"
apply_endpoint_id="$(create_service_connection dual-pipeline-azdo-apply azure_pipelines_apply)"

github_endpoint_id="$(
  jq -er \
    --arg name "$github_connection_name" \
    '[.value[] |
      select(.name == $name and
             (.type | ascii_downcase) == "github" and
             .authorization.scheme == "InstallationToken")][0].id' \
    "$endpoints_json"
)"

definitions_json="$temp_dir/definitions.json"
devops_rest \
  --method get \
  --url "$api_root/build/definitions?api-version=7.1" \
  -o json >"$definitions_json"
pipeline_id="$(
  jq -r --arg name "$pipeline_name" \
    '[.value[] | select(.name == $name)][0].id // empty' \
    "$definitions_json"
)"

hosted_queue_json="$(
  devops_rest \
    --method get \
    --url "$api_root/distributedtask/queues?api-version=7.1" \
    -o json |
    jq -ec '[.value[] | select(.name == "Azure Pipelines")][0]'
)"
hosted_queue_id="$(jq -er '.id' <<<"$hosted_queue_json")"
hosted_pool_id="$(jq -er '.pool.id' <<<"$hosted_queue_json")"

if [[ -z "$pipeline_id" ]]; then
  pipeline_payload="$temp_dir/pipeline.json"
  jq -n \
    --arg name "$pipeline_name" \
    --arg repo "$repo" \
    --arg github_endpoint_id "$github_endpoint_id" \
    --arg state_resource_group "$state_resource_group" \
    --arg state_storage_account "$state_storage_account" \
    --arg state_container "$azdo_state_container" \
    --arg target_resource_group "$azdo_target_resource_group" \
    --arg owner "$owner" \
    --arg expires_on "$expires_on" \
    --arg approval_user "$approval_user" \
    --argjson hosted_queue_id "$hosted_queue_id" \
    --argjson hosted_pool_id "$hosted_pool_id" \
    '{
      name: $name,
      path: "\\",
      type: "build",
      queueStatus: "enabled",
      queue: {
        id: $hosted_queue_id,
        name: "Azure Pipelines",
        pool: {
          id: $hosted_pool_id,
          name: "Azure Pipelines",
          isHosted: true
        }
      },
      process: {type: 2, yamlFilename: "azure-pipelines.yml"},
      repository: {
        id: $repo,
        name: $repo,
        type: "GitHub",
        url: ("https://github.com/" + $repo),
        defaultBranch: "refs/heads/main",
        clean: "true",
        checkoutSubmodules: false,
        properties: {
          apiUrl: ("https://api.github.com/repos/" + $repo),
          connectedServiceId: $github_endpoint_id,
          defaultBranch: "main"
        }
      },
      variables: {
        STATE_RESOURCE_GROUP: {value: $state_resource_group},
        STATE_STORAGE_ACCOUNT: {value: $state_storage_account},
        AZURE_DEVOPS_STATE_CONTAINER: {value: $state_container},
        AZURE_DEVOPS_TARGET_RESOURCE_GROUP: {value: $target_resource_group},
        RESOURCE_OWNER: {value: $owner},
        EXPIRES_ON: {value: $expires_on},
        APPROVAL_NOTIFY_USERS: {value: $approval_user}
      }
    }' >"$pipeline_payload"
  pipeline_id="$(
    devops_rest \
      --method post \
      --url "$api_root/build/definitions?api-version=7.1" \
      --headers Content-Type=application/json \
      --body "@$pipeline_payload" \
      --query id \
      -o tsv
  )"
fi

for endpoint_id in "$plan_endpoint_id" "$apply_endpoint_id"; do
  permission_payload="$temp_dir/permission-$endpoint_id.json"
  jq -n \
    --argjson pipeline_id "$pipeline_id" \
    '{pipelines: [{id: $pipeline_id, authorized: true}]}' >"$permission_payload"
  devops_rest \
    --method patch \
    --url "$api_root/pipelines/pipelinepermissions/endpoint/$endpoint_id?api-version=7.1-preview.1" \
    --headers Content-Type=application/json \
    --body "@$permission_payload" \
    -o none
done

printf 'Configured Azure Pipeline %s with two Microsoft Entra-issued service connections.\n' "$pipeline_name"
