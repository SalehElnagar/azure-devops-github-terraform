# Accepted lab risks

The release scans the repository with Checkov, Trivy, Semgrep, Gitleaks, ShellCheck,
Terraform, and the project test suite. The following scanner findings are suppressed
at the affected resource, with the rationale kept beside the code:

- Public storage endpoints are required because the proof uses GitHub-hosted and
  Microsoft-hosted runners. Shared-key access and anonymous container access remain
  disabled, and each state container has its own federated RBAC scope.
- The static website is intentionally public demonstration output. It contains no
  customer data and is destroyed at the end of the lifecycle.
- LRS and Microsoft-managed encryption are accepted for this short-lived,
  non-production lab. A durable backend should use the organization's approved
  replication and customer-managed-key standards.
- Storage Analytics and private endpoints need additional monitoring and
  network-integrated runner infrastructure that is outside this self-contained proof.
- The GitHub dispatch input is a two-value `apply`/`destroy` enum. Its value is bound
  into the saved-plan metadata and checked again before apply.

These are scope decisions, not production recommendations. The repository's
`README.md` and `SECURITY.md` describe the stronger production boundary.
