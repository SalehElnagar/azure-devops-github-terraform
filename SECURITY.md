# Security Policy

## Demonstration boundary

This repository is a reference implementation, not a managed deployment service. Run it
only in an isolated Azure subscription and Azure DevOps project where you are authorized
to create and remove identities, role assignments, service connections, pipelines,
storage accounts, and resource groups.

## Non-negotiable controls

- Never commit Azure client secrets, certificates, storage keys, SAS tokens, PATs,
  Terraform state, saved plans, local variable files, or live tenant/subscription/client
  identifiers.
- Use the exact immutable GitHub OIDC subject returned for the repository.
- Use Microsoft Entra-issued Azure DevOps workload-identity service connections. Do not
  create new connections with the deprecated Azure DevOps issuer.
- Authorize service connections only for the intended pipeline.
- Keep pull-request validation free of cloud identity and `id-token: write`.
- Keep one apply owner per target resource group and state container.
- Treat state, provider caches, plans, plan text, pipeline artifacts, and bootstrap
  outputs as sensitive operational data.
- Require plan and apply to use the same commit, operation, toolchain, provider lockfile,
  backend, variables, and saved-plan digest.

## Least-privilege model

Each orchestrator receives:

- a plan identity with Reader on its assigned target resource group and state/data-plane
  read access required to produce a plan; and
- an apply identity with Contributor on only its assigned target resource group plus the
  workload data-plane role and state-container access required to apply.

No pipeline identity receives subscription-wide Contributor.

The plan identities currently receive Storage Blob Data Contributor on their isolated
state containers because Terraform state locking requires blob writes. The target
resource groups remain read-only to the plan identities.

## Bootstrap state

The ephemeral lab uses an ignored local bootstrap state so it can safely destroy the
storage account created by that same state. Protect the workstation, keep `local/`
outside synchronization and backup systems that are not approved for sensitive data,
and remove it after cleanup.

For production or repeated use, move bootstrap state to a separately administered
pre-existing backend. Never place bootstrap state in a storage account that the same
state is expected to destroy.

## Plan artifact handling

Saved plans can contain sensitive values and infrastructure topology. Both pipelines:

- retain the plan artifact for one day;
- create it only in a trusted, federated job;
- carry plan metadata with commit, operation, digests, Terraform version, and timestamp;
- reject a digest, commit, operation, provider-lock, or freshness mismatch; and
- apply only the verified binary plan.

Do not upload plan JSON or raw state to the public repository or issue tracker.

## Incident response

To stop deployment during an incident:

1. Disable the GitHub workflow and Azure Pipeline.
2. Disable or remove the federated credentials on all four managed identities.
3. Disable the two Azure DevOps service connections.
4. Revoke target and state role assignments if compromise is suspected.
5. Preserve run logs and state versions under incident retention controls.
6. Inspect state locks before force-unlocking; never force-unlock an active operation.
7. Re-establish trust, produce a fresh plan, and require a no-change or explicitly
   reviewed remediation plan before resuming.

To recover state, use Azure Blob version history under a documented change and test the
restored state with a read-only plan. Do not manually edit state blobs.

## Reporting a vulnerability

Use GitHub private vulnerability reporting for this repository. Do not include
credentials, tokens, tenant identifiers, subscription identifiers, live resource names,
state, plan files, or customer data in a public issue.
