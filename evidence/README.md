# Validation evidence

`manifest.json` is the sanitized, committed validation record. It records the tested
source commit, exact tool/provider versions, runner images, immutable action SHAs,
lifecycle outcomes, security-scan outcomes, and verified cleanup.

Raw GitHub, Azure DevOps, Terraform, and Azure CLI output belongs in `evidence/raw/`,
which is ignored. Raw output can contain resource identifiers, plan values, federated
subjects, or internal URLs and must not be published.

The public manifest intentionally records outcomes rather than raw logs. GitHub Actions
run history remains available through the public repository; Azure DevOps evidence is
summarized because the demonstration project is not public.

Scanner suppressions are resource-scoped and documented in
[`accepted-risks.md`](accepted-risks.md). A suppression means the lab boundary was
reviewed and accepted; it does not convert the exception into a production control.
