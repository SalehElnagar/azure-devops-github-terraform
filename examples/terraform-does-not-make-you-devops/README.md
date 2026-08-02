# Terraform Does Not Make You DevOps: Executable Azure Lab

This lab deploys one Terraform workload-foundation module through two operating
models. The Azure resources are intentionally inexpensive and disposable, but the
delivery differences are real and executable.

| Path | Tooling | State | Operating capabilities |
| --- | --- | --- | --- |
| `provisioning-only/` | Terraform | Local state | Secure core resources, but no defined observability, recovery, delete protection, or shared delivery contract |
| `platform/live/dev/foundation/` | Terraform through Terragrunt | Azure Blob remote state with Microsoft Entra authorization | Reusable inputs, centralized state configuration, observability, recovery, delete protection, and explicit ownership metadata |

Terragrunt is not presented as a shortcut to becoming DevOps. It is used as one
mechanism for centralizing an operating contract. The engineering decisions around
state, review, security, evidence, recovery, and ownership remain the important part.

## Layout

```text
.
├── RUNBOOK.md                    # Human-executed saved-plan lifecycle
├── bootstrap/                    # Temporary Azure Blob state backend
├── modules/workload-foundation/  # Reusable Terraform contract and native tests
├── provisioning-only/            # Direct, task-oriented Terraform root
├── platform/
│   ├── root.hcl                  # Shared Terragrunt backend/provider policy
│   └── live/dev/foundation/      # Self-service environment inputs
├── scripts/                      # Local validation and repository artifact guard
├── tests/                        # Repository contract tests
└── evidence/                     # Sanitized evidence only; never credentials or raw state
```

## Local validation

Prerequisites:

- Terraform `1.14.7`
- Terragrunt `1.0.4`
- AzureRM provider `4.81.0`
- Python 3 and ShellCheck

Run:

```bash
make validate
```

The validation path does not authenticate to Azure. It checks Terraform formatting,
initializes without either live backend, validates all roots, executes native Terraform
tests with mocked providers, validates Terragrunt HCL, runs repository contract tests,
and checks shell scripts.

## Live Azure boundary

Live plans, applies, drift probes, and destroys are separate from local validation.
They must target an isolated non-production subscription, use unique prefixes and
short expiry tags, and be executed from reviewed saved plans. See `RUNBOOK.md` once
the implementation candidate has passed local validation.

Do not commit:

- Terraform state or saved plans;
- Azure subscription, tenant, or object identifiers;
- Azure CLI output containing identity context;
- credentials, access keys, SAS tokens, client secrets, or `.env` files; or
- raw evidence that has not been sanitized.

## Source repository

This example is maintained in
[`SalehElnagar/azure-devops-github-terraform`](https://github.com/SalehElnagar/azure-devops-github-terraform/tree/main/examples/terraform-does-not-make-you-devops).
The link becomes authoritative only after this directory is reviewed and pushed.
