# Sanitized validation summary

This note records the evidence used by the accompanying article without
publishing Azure identifiers, raw plans, Terraform state, credentials, or
identity context.

## Scope

- Validation date: 2026-08-02
- IaC baseline: commit `bee84435cdd25d4aa55ee99b7b147f5f730e7040`
- Terraform: 1.14.7, resolved through `mise` by `scripts/validate.sh`
- Terragrunt: 1.0.4
- AzureRM provider: 4.81.0
- Random provider: 3.9.0

The IaC files in the baseline above are unchanged by the later editorial-only
article revision.

## Reproducible local checks

Run from this example directory:

```bash
make validate
gitleaks detect --no-git --source . --no-banner
checkov --directory . --framework terraform --compact
trivy config \
  --severity HIGH,CRITICAL \
  --exit-code 1 \
  --skip-dirs '**/.terraform/**' \
  --skip-dirs '**/.terragrunt-cache/**' \
  .
```

Observed results:

| Check | Tool version | Result |
| --- | --- | --- |
| Terraform native tests | Terraform 1.14.7 | 6 runs passed, 0 failed |
| Repository contract tests | Python unittest | 8 passed, 0 failed |
| Terragrunt HCL and strict input validation | Terragrunt 1.0.4 | Passed |
| Shell analysis | ShellCheck 0.11.0 | Passed |
| Secret scanning | Gitleaks 8.30.1 | No leaks found |
| Terraform static analysis | Checkov 3.2.530 | 18 passed, 0 failed, 6 documented skips |
| High and critical IaC findings | Trivy 0.71.0 | 0 unsuppressed findings |

Scanner versions and policy bundles change over time, so future runs may report
different totals even when the source is unchanged. A changed total must be
reviewed rather than assumed to be equivalent.

## Azure evidence boundary

The isolated Azure validation established the following:

- The temporary Azure Blob state backend was applied and queried successfully;
  provisioning state and the required project, owner, expiry, and purpose tags
  were observed.
- The storage account was observed with TLS 1.2, HTTPS-only traffic, public blob
  access disabled, shared-key access disabled, and default OAuth authorization.
- Blob-service queries observed versioning, seven-day blob deletion retention,
  and seven-day container deletion retention.
- The state container was observed as private, with one Storage Blob Data
  Contributor assignment scoped to that container.
- Storage shared-key access was disabled, and Terragrunt initialized the backend
  through Microsoft Entra authorization.
- A data-plane existence query observed the expected
  `live/dev/foundation/terraform.tfstate` object.
- A bootstrap convergence plan reported no changes.
- The direct Terraform workload plan proposed 10 creates.
- The Terragrunt platform workload plan proposed 14 creates, including Log
  Analytics, Application Insights, NSG diagnostics, and a delete lock.

The workload applies, post-apply convergence checks, live telemetry and lock
queries, drift and recovery exercises, workload teardown, and final backend
cleanup were not observed. The article therefore labels those lifecycle claims
as pending.
