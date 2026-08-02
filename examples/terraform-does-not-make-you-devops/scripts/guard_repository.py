#!/usr/bin/env python3
"""Fail when the example contains generated state, local identity data, or literal secrets."""

from __future__ import annotations

import pathlib
import re
import sys


EXAMPLE_ROOT = pathlib.Path(__file__).resolve().parents[1]
GENERATED_DIRECTORIES = {".terraform", ".terragrunt-cache", "__pycache__"}
RUNTIME_SUFFIXES = {".tf", ".hcl", ".sh"}
REQUIRED_IGNORE_RULES = {
    "**/.terraform/",
    "**/.terragrunt-cache/",
    "*.tfstate",
    "*.tfstate.*",
    "*.tfplan",
    "*.tfplan.*",
    "*.auto.tfvars",
    "*.tfvars",
    "!*.tfvars.example",
    ".env",
    ".env.*",
    "evidence/local/",
    "evidence/raw/",
    "evidence/private/",
}
LITERAL_SECRET = re.compile(
    r"(?im)^\s*(?:access_key|client_secret|password|sas_token)\s*=\s*[\"'][^$\"']+[\"']"
)


def main() -> int:
    violations: list[str] = []
    ignore_rules = {
        line.strip()
        for line in (EXAMPLE_ROOT / ".gitignore").read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    }

    for missing_rule in sorted(REQUIRED_IGNORE_RULES - ignore_rules):
        violations.append(f"missing ignore rule: {missing_rule}")

    for path in sorted(EXAMPLE_ROOT.rglob("*")):
        relative = path.relative_to(EXAMPLE_ROOT)

        if any(part in GENERATED_DIRECTORIES for part in relative.parts):
            violations.append(f"generated directory: {relative}")
            continue

        if path.is_dir():
            continue

        if path.name == ".env" or path.name.startswith(".env."):
            violations.append(f"environment file: {relative}")

        if (
            ".tfstate" in path.name
            or ".tfplan" in path.name
            or path.name.endswith(".auto.tfvars")
        ):
            violations.append(f"state or plan artifact: {relative}")

        if path.suffix == ".tfvars" and not path.name.endswith(".tfvars.example"):
            violations.append(f"runtime variable file: {relative}")

        if relative.parts[:2] in {
            ("evidence", "local"),
            ("evidence", "raw"),
            ("evidence", "private"),
        }:
            violations.append(f"unsanitized evidence path: {relative}")

        if path.suffix in RUNTIME_SUFFIXES:
            content = path.read_text(encoding="utf-8")
            if LITERAL_SECRET.search(content):
                violations.append(f"literal secret assignment: {relative}")

    if violations:
        for violation in violations:
            print(violation, file=sys.stderr)
        return 1

    print("Repository guard passed: no generated state, local identity data, or literal secrets.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
