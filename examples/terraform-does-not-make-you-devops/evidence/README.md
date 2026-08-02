# Evidence handling

This directory accepts sanitized, reviewable evidence only. Raw Terraform plans,
state, Azure identity output, and full command transcripts must remain outside the
repository in a mode-0700 temporary directory. The local ignore rules are defense
in depth, not permission to retain sensitive artifacts under this tree.

Evidence claims use these levels:

1. `static-configuration` — a property exists in reviewed source;
2. `local-test` — a mocked Terraform test or repository test observed it;
3. `azure-observed` — a sanitized Azure query observed it after apply;
4. `lifecycle-observed` — apply, no-change plan, drift detection, correction, and
   destroy were observed for the same candidate and target.

No claim may be upgraded merely because a command was documented or expected to
work.

The publishable outcome summary is recorded in
[`validation-summary.md`](validation-summary.md). It reports bounded results and
tool versions without including raw Azure or Terraform artifacts.
