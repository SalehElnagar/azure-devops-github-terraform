#!/usr/bin/env python3

import pathlib
import re
import unittest


EXAMPLE_ROOT = pathlib.Path(__file__).resolve().parents[1]


class RepositoryContractTests(unittest.TestCase):
    def read(self, relative_path: str) -> str:
        return (EXAMPLE_ROOT / relative_path).read_text(encoding="utf-8")

    def test_ticket_driven_path_exposes_missing_operational_contract(self) -> None:
        main = self.read("provisioning-only/main.tf")
        self.assertIn('operating_model      = "ticket-driven"', main)
        self.assertIn("enable_observability = false", main)
        self.assertIn("enable_recovery      = false", main)
        self.assertIn("enable_delete_lock   = false", main)

    def test_platform_path_enables_the_operational_contract(self) -> None:
        config = self.read("platform/live/dev/foundation/terragrunt.hcl")
        self.assertIn('operating_model      = "devops-platform"', config)
        self.assertIn("enable_observability = true", config)
        self.assertIn("enable_recovery      = true", config)
        self.assertIn("enable_delete_lock   = true", config)
        self.assertIn("lifecycle_phase      = local.environment_config.locals.lifecycle_phase", config)

    def test_platform_requires_ownership_and_expiry_inputs(self) -> None:
        config = self.read("platform/live/dev/environment.hcl")
        self.assertIn('name_prefix     = get_env("LAB_NAME_PREFIX")', config)
        self.assertIn('owner           = get_env("LAB_OWNER")', config)
        self.assertIn('expires_on      = get_env("LAB_EXPIRES_ON")', config)
        self.assertIn('lifecycle_phase = get_env("LAB_LIFECYCLE_PHASE", "operate")', config)

    def test_terragrunt_uses_remote_state_and_entra_authorization(self) -> None:
        root = self.read("platform/root.hcl")
        self.assertIn('backend = "azurerm"', root)
        self.assertIn("use_azuread_auth     = true", root)
        self.assertIn('key                  = "${path_relative_to_include()}/terraform.tfstate"', root)
        self.assertNotIn("access_key", root)
        self.assertNotIn("sas_token", root)

    def test_module_enforces_secure_storage_defaults(self) -> None:
        module = self.read("modules/workload-foundation/main.tf")
        self.assertIn("shared_access_key_enabled         = false", module)
        self.assertIn("default_to_oauth_authentication   = true", module)
        self.assertIn("public_network_access_enabled     = false", module)
        self.assertIn('default_action = "Deny"', module)
        self.assertIn('bypass         = ["None"]', module)
        self.assertIn('resource "azurerm_private_endpoint" "storage_blob"', module)
        self.assertIn("versioning_enabled = true", module)

    def test_production_guard_is_apply_blocking(self) -> None:
        module = self.read("modules/workload-foundation/main.tf")
        self.assertIn("lifecycle {", module)
        self.assertIn("precondition {", module)
        self.assertNotIn('check "production_operability"', module)

    def test_runtime_configuration_has_no_committed_azure_uuid(self) -> None:
        uuid_pattern = re.compile(
            r"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-"
            r"[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b"
        )
        runtime_files = [
            *EXAMPLE_ROOT.glob("bootstrap/*.tf"),
            *EXAMPLE_ROOT.glob("provisioning-only/*.tf"),
            *EXAMPLE_ROOT.glob("platform/**/*.hcl"),
            *EXAMPLE_ROOT.glob("modules/workload-foundation/*.tf"),
        ]
        violations = [
            str(path.relative_to(EXAMPLE_ROOT))
            for path in runtime_files
            if uuid_pattern.search(path.read_text(encoding="utf-8"))
        ]
        self.assertEqual([], violations)

    def test_only_example_tfvars_are_committed(self) -> None:
        unsafe_tfvars = [
            str(path.relative_to(EXAMPLE_ROOT))
            for path in EXAMPLE_ROOT.rglob("*.tfvars")
            if not path.name.endswith(".tfvars.example")
        ]
        self.assertEqual([], unsafe_tfvars)


if __name__ == "__main__":
    unittest.main()
