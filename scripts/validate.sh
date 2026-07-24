#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

terraform fmt -check -recursive bootstrap infra
terraform -chdir=infra init -backend=false -input=false
terraform -chdir=infra validate
terraform -chdir=infra test
python3 -m unittest discover -s tests -p 'test_*.py'
for shell_test in tests/test_*.sh; do
  bash "$shell_test"
done
shellcheck scripts/*.sh tests/*.sh
