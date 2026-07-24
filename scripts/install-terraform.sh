#!/usr/bin/env bash
set -euo pipefail

terraform_version="${TERRAFORM_VERSION:-1.14.7}"
terraform_sha256="${TERRAFORM_LINUX_AMD64_SHA256:-e8bbcefea8015156e04e2a325cde37a0b2fb761728bda548e2fe3b8ad7c18c96}"

if command -v terraform >/dev/null 2>&1; then
  installed_version="$(terraform version -json | jq -er '.terraform_version')"
  if [[ "$installed_version" == "$terraform_version" ]]; then
    printf 'Terraform %s is already installed.\n' "$terraform_version"
    exit 0
  fi
fi

archive="terraform_${terraform_version}_linux_amd64.zip"
download_dir="$(mktemp -d)"
trap 'rm -rf "$download_dir"' EXIT

curl --fail --silent --show-error --location \
  "https://releases.hashicorp.com/terraform/${terraform_version}/${archive}" \
  --output "$download_dir/$archive"
printf '%s  %s\n' "$terraform_sha256" "$download_dir/$archive" | sha256sum --check
unzip -q "$download_dir/$archive" -d "$download_dir"
sudo install -m 0755 "$download_dir/terraform" /usr/local/bin/terraform
terraform version
