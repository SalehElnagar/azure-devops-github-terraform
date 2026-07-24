# Terraform on Azure: GitHub Actions and Azure Pipelines

One GitHub repository, one Terraform workload, and two isolated, federated Azure
deployment paths.

This repository is an executable, security-focused comparison of GitHub Actions and
Azure Pipelines as Terraform orchestrators. It demonstrates that repository hosting
and pipeline orchestration can be evaluated independently without weakening Terraform
state ownership, identity boundaries, approvals, or auditability.

The two paths deploy the same static-website Terraform root through:

- GitHub Actions with GitHub OIDC;
- Azure Pipelines connected to the GitHub repository through the Azure Pipelines
  GitHub App; and
- four user-assigned managed identities: a plan and apply identity for each path.

Each orchestrator has its own state container, target resource group, approval gate,
apply identity, and concurrency boundary. Neither path stores an Azure client secret,
certificate, storage key, SAS token, or deployment PAT.

## Architecture and invariants

```text
GitHub repository
├── GitHub Actions
│   ├── plan identity → approval → apply identity
│   ├── github-actions state container
│   └── GitHub-owned target resource group
└── Azure Pipelines
    ├── plan connection → manual validation → apply connection
    ├── azure-pipelines state container
    └── Azure DevOps-owned target resource group
```

The implementation enforces these rules:

1. One Terraform state, one environment, one designated apply owner.
2. Pull-request validation has no Azure login and cannot request an OIDC token.
3. Plan identities can read the target; only apply identities can change it.
4. Apply verifies the reviewed plan digest, provider-lock digest, operation, commit,
   and maximum plan age before invoking Terraform.
5. GitHub Actions are pinned to immutable commits; Terraform and providers are pinned
   exactly and both lockfiles are committed.
6. GitHub concurrency and Azure Pipelines sequential stage locking serialize each
   lifecycle lane.

## Repository layout

```text
.
├── .github/workflows/       # Unprivileged validation and protected lifecycle
├── bootstrap/               # State, identities, federation, target groups, RBAC
├── environments/            # Non-secret workload inputs
├── evidence/                # Sanitized lifecycle and validation evidence
├── infra/                   # Shared Terraform workload and native tests
├── scripts/                 # Lifecycle, setup, and validation helpers
├── tests/                   # Repository, lifecycle, and evidence tests
└── azure-pipelines.yml      # Serialized Azure plan, review, and apply stage
```

## Prerequisites

- Terraform 1.14.7
- Azure CLI 2.87.0 or a compatible later patch
- GitHub CLI authenticated with repository, workflow, and environment permissions
- `jq`, Python 3, ShellCheck, and GNU Make
- An Azure subscription where you can create resource groups, managed identities,
  role assignments, and storage accounts
- An Azure DevOps project where you can create service connections and pipelines
- The Azure Pipelines GitHub App installed for the companion repository

Use an isolated non-production Azure subscription for the live lab. All resources are
temporary, tagged with owner and expiry metadata, and must be destroyed at the end.

## Validate locally

```bash
make validate
```

This runs Terraform formatting, initialization without the workload backend, validation,
native Terraform tests, Python repository-policy tests, lifecycle tamper tests, evidence
sanitization tests, and ShellCheck.

## Bootstrap the lab

The bootstrap root deliberately uses an ignored local state file under `local/` because
the lab must destroy the storage account it creates. Protect this workstation state and
remove it after verified cleanup.

For a durable environment, do **not** copy this exception. Bootstrap state should live
in a separately owned, pre-existing remote backend that is outside the lifecycle of the
resources in this root.

1. Create or fork the GitHub repository.
2. Enable immutable GitHub OIDC subjects and obtain the exact subject prefix:

   ```bash
   ./scripts/configure-github.sh oidc-subject \
     --repo OWNER/azure-devops-github-terraform
   ```

3. Copy `bootstrap/terraform.tfvars.example` to an ignored file such as
   `local/bootstrap.tfvars`. Set:

   - a short lowercase `name_prefix`;
   - the resource `owner` and ISO `expires_on` date;
   - your Microsoft Entra operator object ID; and
   - the immutable GitHub subject prefix from the previous command.

4. Initialize, review, and apply bootstrap:

   ```bash
   terraform -chdir=bootstrap init -reconfigure -input=false
   terraform -chdir=bootstrap plan \
     -input=false \
     -var-file=../local/bootstrap.tfvars \
     -out=../local/bootstrap.tfplan
   terraform -chdir=bootstrap apply \
     -input=false \
     ../local/bootstrap.tfplan
   terraform -chdir=bootstrap output -json \
     >local/bootstrap-output.json
   ```

5. Configure GitHub variables and the `dev` and `dev-destroy` environments:

   ```bash
   ./scripts/configure-github.sh configure \
     --repo OWNER/azure-devops-github-terraform \
     --bootstrap-output local/bootstrap-output.json \
     --reviewer OWNER
   ```

   Required reviewers on GitHub Free, Pro, and Team are available only for public
   repositories. This lab permits the initiating owner to approve their own deployment
   so one person can execute the proof. Production environments should prevent
   self-review and use independent approvers.

6. Configure the two Entra-issued Azure Resource Manager service connections and the
   Azure Pipeline:

   ```bash
   ./scripts/configure-azure-devops.sh \
     --organization https://dev.azure.com/ORGANIZATION \
     --project PROJECT \
     --repo OWNER/azure-devops-github-terraform \
     --bootstrap-output local/bootstrap-output.json
   ```

   The script creates `dual-pipeline-azdo-plan` and
   `dual-pipeline-azdo-apply`, verifies their issuer is Microsoft Entra rather
   than the deprecated Azure DevOps issuer, adds managed-identity federated
   credentials, creates the YAML pipeline, and authorizes only that pipeline to use
   the service connections.

## Run the lifecycle

Run each phase against the same source commit in both orchestrators:

1. `apply` to create both isolated websites;
2. one shared edit to `infra/site/index.html.tftpl`, then `apply`;
3. another `apply` of the same commit to demonstrate no change; and
4. `destroy` through each owning pipeline.

For GitHub Actions, dispatch **Terraform lifecycle** and approve the `dev` or
`dev-destroy` environment. For Azure Pipelines, queue the pipeline with the matching
operation and approve the Manual Validation job after reviewing the plan digest,
operation, and commit.

The committed workload variable example is intentionally non-secret. Backend locations,
target group names, tenant/subscription identifiers, and client IDs are configured as
repository or pipeline variables and are not committed.

## Cleanup

Destroy workload stacks before bootstrap:

1. Run GitHub Actions with `operation=destroy`.
2. Run Azure Pipelines with `operation=destroy`.
3. Confirm both target resource groups contain no workload resources.
4. Delete the two temporary Azure DevOps service connections and pipeline if they are
   no longer needed.
5. Run:

   ```bash
   terraform -chdir=bootstrap destroy \
     -input=false \
     -var-file=../local/bootstrap.tfvars
   ```

6. Verify that no resource groups tagged `project=dual-pipeline-terraform` remain.
7. Remove the ignored local state, plan, output, and raw-evidence files.

Never delete the state storage account before both workload destroys have completed.
See [SECURITY.md](SECURITY.md) for incident and recovery guidance.

## Demonstration limits

- Public network access is enabled on the temporary state account because both hosted
  runner pools need to reach it. Microsoft Entra authentication, disabled shared keys,
  private containers, and container-scoped RBAC remain enforced. Production designs
  should prefer private endpoints and network-integrated runners.
- The lab uses self-approval to keep the proof executable by one author. Production
  separation of duties should prevent it.
- A static website is used as visible deployment evidence. This is not a complete Azure
  landing zone or application architecture.
- Azure DevOps pipeline tasks are platform-managed by major task version. GitHub Actions
  are third-party repository dependencies and are pinned to full commit SHAs.

## License

MIT. See [LICENSE](LICENSE).
