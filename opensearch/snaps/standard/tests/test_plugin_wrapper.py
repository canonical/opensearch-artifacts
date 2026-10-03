"""Test the Bash plugin entrypoint against real files and a recording native command."""

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1] / "scripts"


@unittest.skipUnless(
    sys.platform.startswith("linux"), "The snap wrapper uses GNU readlink; run in the VM."
)
class PluginWrapperTests(unittest.TestCase):
    """Ensure the wrapper protects bundled plugins before invoking the native CLI."""

    def setUp(self) -> None:
        """Build a private snap layout with the actual wrapper and configuration helper."""
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.snap_data_root = Path(temporary.name)
        snap = self.snap_data_root / "snap/102"
        self.config_dir = self.snap_data_root / "common/etc/opensearch"
        self.config_dir.mkdir(parents=True)
        (self.snap_data_root / "common/home/snap_daemon").mkdir(parents=True)
        (self.snap_data_root / "102/usr/share/opensearch/plugins").mkdir(parents=True)
        (snap / "usr/bin").mkdir(parents=True)
        (snap / "usr/bin/python3").symlink_to(sys.executable)
        (snap / "opt/opensearch/helpers").mkdir(parents=True)
        shutil.copyfile(
            SOURCE / "helpers/plugin-configuration.py",
            snap / "opt/opensearch/helpers/plugin-configuration.py",
        )
        self.environment = dict(
            os.environ,
            SNAP=str(snap),
            SNAP_DATA=str(self.snap_data_root / "102"),
            SNAP_COMMON=str(self.snap_data_root / "common"),
            OPENSEARCH_PATH_CONF=str(self.config_dir),
        )

    def configuration(self, directory: str, content: str) -> None:
        """Create a plugin configuration file whose preservation can be checked."""
        target = self.config_dir / directory
        target.mkdir()
        (target / "settings.yml").write_text(content)

    def wrapper(self, *arguments: str, expected_exit: int = 0) -> subprocess.CompletedProcess[str]:
        """Invoke the actual Bash wrapper, which chooses its own native executable."""
        result = subprocess.run(
            ["bash", str(SOURCE / "wrappers/plugin-wrapper.sh"), *arguments],
            env=self.environment,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, expected_exit, result.stderr)
        return result

    def bundled_plugin(self) -> Path:
        """Create a bundled plugin and a command that records any native invocation."""
        shipped = (
            Path(self.environment["SNAP"]) / "usr/share/opensearch/shipped-plugins/fixture-core"
        )
        shipped.mkdir(parents=True)
        (shipped / "plugin-descriptor.properties").write_text("name=fixture-core\n")
        plugin_link = self.snap_data_root / "102/usr/share/opensearch/plugins/fixture-core"
        plugin_link.symlink_to(shipped, target_is_directory=True)
        self.configuration("fixture-core", "keep this configuration")
        native_command = (
            Path(self.environment["SNAP"])
            / "usr/share/opensearch/shipped-bin/opensearch-plugin.orig"
        )
        native_command.parent.mkdir(parents=True)
        native_command.write_text(
            "#!/bin/sh\n" 'printf "%s\\n" "$@" > "$SNAP_COMMON/native-arguments"\n'
        )
        native_command.chmod(0o755)
        return plugin_link

    def test_bundled_removal_never_reaches_native_command(self) -> None:
        """Reject native removal spellings before they can change plugin or config files."""
        plugin_link = self.bundled_plugin()
        # Cover option placement, a missing link, and path spellings accepted by native removal.
        for arguments in [
            ["remove", "fixture-core"],
            ["remove", "--purge", "fixture-core"],
            ["remove", "fixture-core", "-p"],
            ["--silent", "remove", "-vp", "fixture-core"],
            ["remove", "-Enode.name=check", "--purge", "fixture-core"],
            ["remove", "-E", "node.name=check", "fixture-core"],
            ["remove", "--", "fixture-core"],
            ["remove", "./fixture-core"],
            ["remove", str(plugin_link)],
            ["remove", "--purge", ""],
            ["remove", "."],
            ["remove", ".."],
        ]:
            with self.subTest(arguments=arguments):
                result = self.wrapper(*arguments, expected_exit=64)
                self.assertIn("opensearch-chiseled", result.stderr)
                self.assertIn("bundled", result.stderr)
                self.assertTrue(plugin_link.is_symlink())
                self.assertEqual(
                    (self.config_dir / "fixture-core/settings.yml").read_text(),
                    "keep this configuration",
                )
                self.assertFalse((self.snap_data_root / "common/native-arguments").exists())
                self.assertFalse(
                    (self.snap_data_root / "102/usr/share/opensearch/plugin-configuration").exists()
                )

    def test_bundled_removal_is_rejected_even_when_link_is_missing(self) -> None:
        """Use the immutable inventory even when only purgeable configuration remains."""
        plugin_link = self.bundled_plugin()
        plugin_link.unlink()
        self.wrapper(
            "remove",
            "--purge",
            "fixture-core",
            expected_exit=64,
        )
        self.assertTrue((self.config_dir / "fixture-core/settings.yml").exists())
        self.assertFalse((self.snap_data_root / "common/native-arguments").exists())

    def test_alias_to_bundled_plugin_cannot_bypass_removal_guard(self) -> None:
        """Resolve aliases so native deletion cannot reach the immutable plugin indirectly."""
        plugin_link = self.bundled_plugin()
        # A lone dash is a native operand, not an option.
        for alias in ["alias", "-"]:
            with self.subTest(alias=alias):
                (plugin_link.parent / alias).symlink_to(plugin_link)
                self.wrapper("remove", "--purge", alias, expected_exit=64)
                self.assertTrue(plugin_link.is_symlink())
                self.assertFalse((self.snap_data_root / "common/native-arguments").exists())

    def test_other_plugin_commands_keep_native_arguments(self) -> None:
        """Leave installation, listing, help and custom removal to the upstream parser."""
        self.bundled_plugin()
        # Help must stay usable; a plugin name in another command is not a removal request.
        for arguments in [
            ["list"],
            ["install", "fixture-core"],
            ["remove", "--help", "fixture-core"],
            ["--help", "remove", "fixture-core"],
            ["-vh", "remove", "fixture-core"],
            ["remove", "-ph", "fixture-core"],
            ["remove", "--he", "fixture-core"],
            ["remove", "-help", "fixture-core"],
            ["remove", "-E", "node.name=/tmp/fixture-core", "custom-folder"],
            ["remove", "--E", "node.name=/tmp/fixture-core", "custom-folder"],
            ["remove", "-vE", "node.name=/tmp/fixture-core", "custom-folder"],
            ["remove", "custom-folder"],
            ["remove", "--purge", "custom-folder"],
            ["remove", "--unknown-option", "custom-folder"],
        ]:
            with self.subTest(arguments=arguments):
                self.wrapper(*arguments)
                self.assertEqual(
                    (self.snap_data_root / "common/native-arguments").read_text().splitlines(),
                    arguments,
                )


if __name__ == "__main__":
    unittest.main()
