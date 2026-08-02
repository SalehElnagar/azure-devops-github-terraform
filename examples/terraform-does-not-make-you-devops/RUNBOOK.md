# Human-executed Azure validation runbook

This runbook proves the example against one explicitly selected, isolated
non-production Azure subscription. It does not grant deployment authority. A
human executor must review every saved plan and receive separate action-time
approval for the exact plan digest before apply or destroy.

## 1. Fixed scope and prerequisites

Use only these roots:

- `bootstrap/` for the temporary Azure Blob state backend;
- `provisioning-only/` for the direct Terraform comparison; and
- `platform/live/dev/foundation/` for the Terragrunt platform path.

Required tools are Terraform `1.14.7`, Terragrunt `1.0.4`, Azure CLI, `jq`, and
`shasum`. The Azure identity needs permission to create the lab resources and
role assignment in the selected subscription. Never substitute another
subscription, tenant, backend, or environment because the intended target is
unavailable.

Before authenticating, record the reviewed Git commit and confirm this example
matches it:

```bash
git rev-parse HEAD
git diff --exit-code HEAD -- examples/terraform-does-not-make-you-devops
git status --short --untracked-files=all -- examples/terraform-does-not-make-you-devops
make -C examples/terraform-does-not-make-you-devops validate
```

The status command must print nothing. This prevents an untracked or modified
example from being mistaken for the recorded commit.

Create a private run directory outside the repository. It may contain plans,
Azure context, and raw command output, so do not copy it into the repository:

```bash
export LAB_RUN_DIR="$(mktemp -d /tmp/terraform-not-devops.XXXXXX)"
chmod 700 "$LAB_RUN_DIR"
```

The human executor must set explicit values. All three prefixes must be unique,
lowercase, alphanumeric, and 4-12 characters long:

```bash
export TARGET_SUBSCRIPTION_ID="<exact-non-production-subscription-id>"
export ARM_SUBSCRIPTION_ID="$TARGET_SUBSCRIPTION_ID"
export LAB_LOCATION="canadacentral"
export LAB_STATE_PREFIX="<unique-state-prefix>"
export LAB_TICKET_PREFIX="<unique-ticket-prefix>"
export LAB_NAME_PREFIX="<unique-platform-prefix>"
export LAB_OWNER="<team-or-owner-alias>"
export LAB_EXPIRES_ON="<yyyy-mm-dd>"
```

Select and verify the exact target. Keep the raw identity response only in the
private run directory:

```bash
az account set --subscription "$TARGET_SUBSCRIPTION_ID"
az account show --output json >"$LAB_RUN_DIR/azure-context.json"
jq '{subscription_id: .id, subscription_name: .name, tenant_id: .tenantId, identity: .user.type}' \
  "$LAB_RUN_DIR/azure-context.json"
```

Stop if the displayed subscription or tenant is not the pre-approved target.

## 2. Approval packet required for every mutation

For each apply, unlock, or destroy, record an owner-controlled packet containing:

- reviewed Git commit and target path;
- Azure subscription and tenant IDs;
- backend resource group, account, container, and state key when applicable;
- human executor identity;
- exact action and expected resource scope;
- saved-plan SHA-256 digest;
- approval expiry; and
- approver identity.

The packet is evidence, not approval. Immediately before the command, a trusted
human must separately approve that exact digest, action, target, executor, and
expiry. The human executor—not an unattended agent—runs the command.

Generate a digest with:

```bash
shasum -a 256 "$LAB_RUN_DIR/<saved-plan>.tfplan"
```

## 3. Bootstrap the keyless remote-state backend

```bash
terraform -chdir=examples/terraform-does-not-make-you-devops/bootstrap init \
  -input=false \
  -reconfigure \
  -backend-config="path=$LAB_RUN_DIR/bootstrap.tfstate"

terraform -chdir=examples/terraform-does-not-make-you-devops/bootstrap plan \
  -input=false \
  -out="$LAB_RUN_DIR/bootstrap.tfplan" \
  -var="name_prefix=$LAB_STATE_PREFIX" \
  -var="location=$LAB_LOCATION" \
  -var="owner=$LAB_OWNER" \
  -var="expires_on=$LAB_EXPIRES_ON"

terraform -chdir=examples/terraform-does-not-make-you-devops/bootstrap show \
  -no-color "$LAB_RUN_DIR/bootstrap.tfplan" >"$LAB_RUN_DIR/bootstrap-plan.txt"
shasum -a 256 "$LAB_RUN_DIR/bootstrap.tfplan"
```

After review, packet matching, and action-time approval, the human executor runs:

```bash
terraform -chdir=examples/terraform-does-not-make-you-devops/bootstrap apply \
  "$LAB_RUN_DIR/bootstrap.tfplan"

terraform -chdir=examples/terraform-does-not-make-you-devops/bootstrap output \
  -json terragrunt_backend >"$LAB_RUN_DIR/backend.json"
```

Export the non-secret backend coordinates:

```bash
export TG_STATE_RESOURCE_GROUP="$(jq -r .resource_group_name "$LAB_RUN_DIR/backend.json")"
export TG_STATE_STORAGE_ACCOUNT="$(jq -r .storage_account_name "$LAB_RUN_DIR/backend.json")"
export TG_STATE_CONTAINER="$(jq -r .container_name "$LAB_RUN_DIR/backend.json")"
```

Role assignment propagation can take time. Do not switch to storage keys if an
Entra-authorized blob query initially fails; retry the same keyless query after
the assignment propagates.

## 4. Validate the ticket-driven Terraform path

Create and review a saved plan:

```bash
terraform -chdir=examples/terraform-does-not-make-you-devops/provisioning-only init \
  -input=false \
  -reconfigure \
  -backend-config="path=$LAB_RUN_DIR/ticket.tfstate"

terraform -chdir=examples/terraform-does-not-make-you-devops/provisioning-only plan \
  -input=false \
  -out="$LAB_RUN_DIR/ticket.tfplan" \
  -var="name_prefix=$LAB_TICKET_PREFIX" \
  -var="location=$LAB_LOCATION" \
  -var="owner=$LAB_OWNER" \
  -var="expires_on=$LAB_EXPIRES_ON"

terraform -chdir=examples/terraform-does-not-make-you-devops/provisioning-only show \
  -no-color "$LAB_RUN_DIR/ticket.tfplan" >"$LAB_RUN_DIR/ticket-plan.txt"
shasum -a 256 "$LAB_RUN_DIR/ticket.tfplan"
```

After the exact apply approval, the human executor runs:

```bash
terraform -chdir=examples/terraform-does-not-make-you-devops/provisioning-only apply \
  "$LAB_RUN_DIR/ticket.tfplan"

terraform -chdir=examples/terraform-does-not-make-you-devops/provisioning-only output \
  -json deployment >"$LAB_RUN_DIR/ticket-output.json"

export TICKET_RESOURCE_GROUP="$(jq -r .resource_group.name "$LAB_RUN_DIR/ticket-output.json")"
```

Observe what exists and what the path intentionally omits:

```bash
jq .operational_capabilities "$LAB_RUN_DIR/ticket-output.json"
az resource list --resource-group "$TICKET_RESOURCE_GROUP" \
  --query '[].{name:name,type:type}' --output table
az lock list --resource-group "$TICKET_RESOURCE_GROUP" --output json
```

Run a no-change plan with the same inputs. Exit code `0` is the expected result;
`2` means drift or a desired change, and `1` means an error:

```bash
terraform -chdir=examples/terraform-does-not-make-you-devops/provisioning-only plan \
  -input=false \
  -detailed-exitcode \
  -var="name_prefix=$LAB_TICKET_PREFIX" \
  -var="location=$LAB_LOCATION" \
  -var="owner=$LAB_OWNER" \
  -var="expires_on=$LAB_EXPIRES_ON"
```

Create a saved destroy plan. Apply it only after a new packet and separate
destroy approval:

```bash
terraform -chdir=examples/terraform-does-not-make-you-devops/provisioning-only plan \
  -destroy \
  -input=false \
  -out="$LAB_RUN_DIR/ticket-destroy.tfplan" \
  -var="name_prefix=$LAB_TICKET_PREFIX" \
  -var="location=$LAB_LOCATION" \
  -var="owner=$LAB_OWNER" \
  -var="expires_on=$LAB_EXPIRES_ON"

terraform -chdir=examples/terraform-does-not-make-you-devops/provisioning-only show \
  -no-color "$LAB_RUN_DIR/ticket-destroy.tfplan" \
  >"$LAB_RUN_DIR/ticket-destroy-plan.txt"
shasum -a 256 "$LAB_RUN_DIR/ticket-destroy.tfplan"

terraform -chdir=examples/terraform-does-not-make-you-devops/provisioning-only apply \
  "$LAB_RUN_DIR/ticket-destroy.tfplan"
az group exists --name "$TICKET_RESOURCE_GROUP"
```

The last command must return `false`.

## 5. Validate the Terragrunt platform path

Start in the protected operating phase:

```bash
export LAB_LIFECYCLE_PHASE="operate"
export PLATFORM_UNIT="examples/terraform-does-not-make-you-devops/platform/live/dev/foundation"
export TG_TF_PATH="terraform"

terragrunt init --working-dir "$PLATFORM_UNIT" -input=false
terragrunt plan --working-dir "$PLATFORM_UNIT" \
  -input=false \
  -out="$LAB_RUN_DIR/platform.tfplan"
terragrunt show --working-dir "$PLATFORM_UNIT" \
  -no-color "$LAB_RUN_DIR/platform.tfplan" >"$LAB_RUN_DIR/platform-plan.txt"
shasum -a 256 "$LAB_RUN_DIR/platform.tfplan"
```

After the exact apply approval, the human executor runs:

```bash
terragrunt apply --working-dir "$PLATFORM_UNIT" "$LAB_RUN_DIR/platform.tfplan"
terragrunt output --working-dir "$PLATFORM_UNIT" \
  -json resource_group >"$LAB_RUN_DIR/platform-resource-group.json"
terragrunt output --working-dir "$PLATFORM_UNIT" \
  -json operational_capabilities >"$LAB_RUN_DIR/platform-capabilities.json"

export PLATFORM_RESOURCE_GROUP="$(jq -r .name "$LAB_RUN_DIR/platform-resource-group.json")"
```

Collect Azure-observed evidence without storage keys:

```bash
jq . "$LAB_RUN_DIR/platform-capabilities.json"
az resource list --resource-group "$PLATFORM_RESOURCE_GROUP" \
  --query '[].{name:name,type:type}' --output table
az lock list --resource-group "$PLATFORM_RESOURCE_GROUP" --output json
az network private-endpoint list --resource-group "$PLATFORM_RESOURCE_GROUP" \
  --query '[].{name:name,state:privateLinkServiceConnections[0].privateLinkServiceConnectionState.status}' \
  --output table
az monitor log-analytics workspace list --resource-group "$PLATFORM_RESOURCE_GROUP" \
  --query '[].{name:name,retention:retentionInDays}' --output table
az storage blob show \
  --auth-mode login \
  --account-name "$TG_STATE_STORAGE_ACCOUNT" \
  --container-name "$TG_STATE_CONTAINER" \
  --name "live/dev/foundation/terraform.tfstate" \
  --output json >"$LAB_RUN_DIR/remote-state-blob.json"
```

Run a no-change plan with `LAB_LIFECYCLE_PHASE=operate`. Exit code `0` is the
expected result:

```bash
terragrunt plan --working-dir "$PLATFORM_UNIT" -input=false -detailed-exitcode
```

Do not test the lock by issuing an ad hoc resource-group deletion. If the lock
were missing, that test would become a real destructive action. The Azure lock
query and Terraform state are the safe evidence for this lab.

## 6. Two-phase protected teardown

The delete lock must be removed through a separately reviewed plan before a
destroy plan is created. Change only the lifecycle phase:

```bash
export LAB_LIFECYCLE_PHASE="teardown"

terragrunt plan --working-dir "$PLATFORM_UNIT" \
  -input=false \
  -out="$LAB_RUN_DIR/platform-unlock.tfplan"
terragrunt show --working-dir "$PLATFORM_UNIT" \
  -no-color "$LAB_RUN_DIR/platform-unlock.tfplan" \
  >"$LAB_RUN_DIR/platform-unlock-plan.txt"
shasum -a 256 "$LAB_RUN_DIR/platform-unlock.tfplan"
```

The reviewed unlock plan must remove the management lock and leave unrelated
resources unchanged. After its own packet and action-time approval, the human
executor applies it and confirms the lock is absent:

```bash
terragrunt apply --working-dir "$PLATFORM_UNIT" "$LAB_RUN_DIR/platform-unlock.tfplan"
az lock list --resource-group "$PLATFORM_RESOURCE_GROUP" --output json
```

Now create, review, approve, and apply the destroy plan:

```bash
terragrunt plan --working-dir "$PLATFORM_UNIT" \
  -destroy \
  -input=false \
  -out="$LAB_RUN_DIR/platform-destroy.tfplan"
terragrunt show --working-dir "$PLATFORM_UNIT" \
  -no-color "$LAB_RUN_DIR/platform-destroy.tfplan" \
  >"$LAB_RUN_DIR/platform-destroy-plan.txt"
shasum -a 256 "$LAB_RUN_DIR/platform-destroy.tfplan"

terragrunt apply --working-dir "$PLATFORM_UNIT" "$LAB_RUN_DIR/platform-destroy.tfplan"
az group exists --name "$PLATFORM_RESOURCE_GROUP"
```

The last command must return `false`.

## 7. Destroy the temporary backend last

Only after the Terragrunt-managed resources are gone, create a saved destroy
plan for the backend. Apply it after a final exact packet and destroy approval:

```bash
terraform -chdir=examples/terraform-does-not-make-you-devops/bootstrap plan \
  -destroy \
  -input=false \
  -out="$LAB_RUN_DIR/bootstrap-destroy.tfplan" \
  -var="name_prefix=$LAB_STATE_PREFIX" \
  -var="location=$LAB_LOCATION" \
  -var="owner=$LAB_OWNER" \
  -var="expires_on=$LAB_EXPIRES_ON"

terraform -chdir=examples/terraform-does-not-make-you-devops/bootstrap show \
  -no-color "$LAB_RUN_DIR/bootstrap-destroy.tfplan" \
  >"$LAB_RUN_DIR/bootstrap-destroy-plan.txt"
shasum -a 256 "$LAB_RUN_DIR/bootstrap-destroy.tfplan"

terraform -chdir=examples/terraform-does-not-make-you-devops/bootstrap apply \
  "$LAB_RUN_DIR/bootstrap-destroy.tfplan"
az group exists --name "$TG_STATE_RESOURCE_GROUP"
```

The last command must return `false`.

## 8. Sanitize evidence and close the run

Publish only the minimum facts needed to support an article claim: candidate
revision, generalized target, timestamps, expected versus observed control,
and pass/fail result. Remove subscription, tenant, object, resource, and storage
identifiers. Never publish raw state, plans, identity output, access tokens, or
full command transcripts.

After sanitized evidence is written and all three resource groups are confirmed
absent, remove the exact temporary directory:

```bash
test -n "$LAB_RUN_DIR"
test -d "$LAB_RUN_DIR"
rm -r "$LAB_RUN_DIR"
```

Any failed apply, no-change plan, unlock, or destroy keeps the related article
claim at `local-test` until the failure is understood and the same candidate and
target complete the lifecycle.
