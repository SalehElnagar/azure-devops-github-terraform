import json
import re
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PUBLIC_TEXT_SUFFIXES = {
    ".md",
    ".html",
    ".yml",
    ".yaml",
    ".tf",
    ".sh",
    ".py",
    ".json",
}
IGNORED_PUBLIC_ROOTS = {"tests"}
ACTION_PATTERN = re.compile(r"uses:\s*[^@\s]+@([0-9a-f]{40})(?:\s|$)")


class RepositoryPolicyTests(unittest.TestCase):
    def public_files(self):
        tracked = subprocess.run(
            ["git", "-C", str(ROOT), "ls-files", "-z"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout
        for relative_name in tracked.split("\0"):
            if not relative_name:
                continue
            relative = Path(relative_name)
            path = ROOT / relative
            if not path.is_file() or path.suffix not in PUBLIC_TEXT_SUFFIXES:
                continue
            if relative.parts[0] in IGNORED_PUBLIC_ROOTS:
                continue
            yield path

    def test_required_public_files_exist(self):
        required = [
            ROOT / "README.md",
            ROOT / "infra" / "main.tf",
            ROOT / "bootstrap" / "main.tf",
            ROOT / ".github" / "workflows" / "terraform.yml",
            ROOT / "azure-pipelines.yml",
            ROOT / "evidence" / "manifest.json",
        ]
        self.assertEqual(
            [],
            [str(path.relative_to(ROOT)) for path in required if not path.exists()],
        )

    def test_public_files_have_no_placeholder_tokens(self):
        forbidden = re.compile(
            r"(?i)(<PINNED_|INSERT REPOSITORY|FIGURE PLACEHOLDER|"
            r"\[insert (?:tested|exact|repository)|TODO\(RELEASE\)|{{SNIPPET:)"
        )
        findings = []
        for path in self.public_files():
            text = path.read_text(encoding="utf-8", errors="replace")
            if forbidden.search(text):
                findings.append(str(path.relative_to(ROOT)))
        self.assertEqual([], findings)

    def test_workflow_actions_are_pinned_to_full_commit(self):
        workflows = list((ROOT / ".github" / "workflows").glob("*.yml"))
        self.assertTrue(workflows)
        unpinned = []
        for workflow in workflows:
            for line_number, line in enumerate(
                workflow.read_text(encoding="utf-8").splitlines(), start=1
            ):
                if "uses:" in line and not ACTION_PATTERN.search(line):
                    unpinned.append(f"{workflow.name}:{line_number}")
        self.assertEqual([], unpinned)

    def test_evidence_manifest_records_cleanup(self):
        manifest_path = ROOT / "evidence" / "manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        self.assertTrue(manifest["cleanup_complete"])
        self.assertRegex(manifest["commit"], r"^[0-9a-f]{40}$")

    def test_evidence_manifest_matches_version_pins(self):
        version_pins = dict(
            line.split("=", 1)
            for line in (ROOT / "versions.env").read_text(encoding="utf-8").splitlines()
            if line
        )
        manifest = json.loads(
            (ROOT / "evidence" / "manifest.json").read_text(encoding="utf-8")
        )

        versions = manifest["versions"]
        template = json.loads(
            (ROOT / "evidence" / "manifest.template.json").read_text(encoding="utf-8")
        )
        self.assertEqual(versions, template["versions"])
        self.assertEqual(version_pins["TERRAFORM_VERSION"], versions["terraform"])
        self.assertEqual(
            version_pins["TERRAFORM_LINUX_AMD64_SHA256"],
            versions["terraform_linux_amd64_sha256"],
        )
        self.assertEqual(
            version_pins["AZURERM_PROVIDER_VERSION"], versions["azurerm"]
        )
        self.assertEqual(version_pins["RANDOM_PROVIDER_VERSION"], versions["random"])
        self.assertEqual(version_pins["AZURE_CLI_VERSION"], versions["azure_cli"])
        self.assertEqual(
            version_pins["GITHUB_RUNNER_IMAGE"],
            versions["runner_images"]["github_actions"],
        )
        self.assertEqual(
            version_pins["AZURE_PIPELINES_IMAGE"],
            versions["runner_images"]["azure_pipelines"],
        )
        self.assertEqual(
            version_pins["ACTION_CHECKOUT_SHA"],
            versions["github_actions"]["checkout"],
        )
        self.assertEqual(
            version_pins["ACTION_SETUP_TERRAFORM_SHA"],
            versions["github_actions"]["setup_terraform"],
        )
        self.assertEqual(
            version_pins["ACTION_AZURE_LOGIN_SHA"],
            versions["github_actions"]["azure_login"],
        )
        self.assertEqual(
            version_pins["ACTION_UPLOAD_ARTIFACT_SHA"],
            versions["github_actions"]["upload_artifact"],
        )
        self.assertEqual(
            version_pins["ACTION_DOWNLOAD_ARTIFACT_SHA"],
            versions["github_actions"]["download_artifact"],
        )

if __name__ == "__main__":
    unittest.main()
