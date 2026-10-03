"""Exercise revision configuration recovery using real files and subprocesses."""

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

HELPER = Path(__file__).resolve().parents[1] / "scripts/helpers/plugin-configuration.py"


class PluginConfigurationTests(unittest.TestCase):
    """Check revision recovery using real files and subprocesses."""

    def setUp(self) -> None:
        """Create two revisions: the older one saves A before live configuration becomes B."""
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.snap_data_root = Path(self.temporary_directory.name)
        self.config_dir = self.snap_data_root / "common/etc/opensearch"
        self.config_dir.mkdir(parents=True)
        (self.snap_data_root / "common/home/snap_daemon").mkdir(parents=True)
        self.environment = dict(
            os.environ,
            SNAP_DATA=str(self.snap_data_root / "102"),
            SNAP_COMMON=str(self.snap_data_root / "common"),
            OPENSEARCH_PATH_CONF=str(self.config_dir),
            SNAP=str(self.snap_data_root / "snap/102"),
        )
        self.plugin("101", "custom-folder")
        self.plugin("102", "custom-folder")
        self.configuration("custom-folder", "configuration A")
        self.helper("save", revision="101")
        (self.config_dir / "custom-folder/settings.yml").write_text("configuration B")
        (self.config_dir / "opensearch.yml").write_text("shared settings")
        (self.config_dir / "certificates").mkdir()
        (self.config_dir / "certificates/ca.pem").write_text("shared certificate")

    def plugin(
        self, revision: str, directory: str, descriptor: str = "name=logical-name\nversion=1.0\n"
    ) -> Path:
        """Create a plugin descriptor in the requested revision."""
        plugin_dir = self.snap_data_root / revision / "usr/share/opensearch/plugins" / directory
        plugin_dir.mkdir(parents=True, exist_ok=True)
        (plugin_dir / "plugin-descriptor.properties").write_text(descriptor)
        return plugin_dir

    def configuration(self, directory: str, content: str) -> Path:
        """Create a plugin-owned configuration directory with known contents."""
        config_dir = self.config_dir / directory
        config_dir.mkdir(exist_ok=True)
        (config_dir / "settings.yml").write_text(content)
        return config_dir

    def helper(
        self, mode: str, *arguments: str, revision: str = "102", expected_exit: int = 0
    ) -> subprocess.CompletedProcess[str]:
        """Run the real helper with the selected revision and assert its exit status."""
        environment = dict(self.environment, SNAP_DATA=str(self.snap_data_root / revision))
        result = subprocess.run(
            [sys.executable, str(HELPER), mode, *arguments],
            env=environment,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, expected_exit, result.stderr)
        return result

    def remove(self, *, purge: bool = True, exit_code: int = 0) -> None:
        """Apply the native removal side effects; integration tests use the actual CLI."""
        # Simulate the native command's filesystem effects; VM tests use the real CLI.
        script = "import pathlib,shutil,sys; "
        script += "shutil.rmtree(pathlib.Path(sys.argv[1])); "
        if purge:
            script += "shutil.rmtree(pathlib.Path(sys.argv[2])); "
        script += f"sys.exit({exit_code})"
        self.helper(
            "run",
            sys.executable,
            "-c",
            script,
            str(self.snap_data_root / "102/usr/share/opensearch/plugins/custom-folder"),
            str(self.config_dir / "custom-folder"),
            "remove",
            expected_exit=exit_code,
        )

    def test_purge_then_revert_restores_the_saved_configuration(self) -> None:
        """Purge then revert restores the saved configuration."""
        self.remove()
        self.assertFalse((self.config_dir / "custom-folder").exists())
        self.helper("restore", revision="101")
        self.assertEqual(
            (self.config_dir / "custom-folder/settings.yml").read_text(), "configuration A"
        )
        self.assertEqual((self.config_dir / "opensearch.yml").read_text(), "shared settings")
        self.assertEqual(
            (self.config_dir / "certificates/ca.pem").read_text(), "shared certificate"
        )

    def test_existing_configuration_is_never_overwritten(self) -> None:
        """Existing configuration is never overwritten."""
        self.remove()
        self.configuration("custom-folder", "configuration C")
        self.helper("restore", revision="101")
        self.assertEqual(
            (self.config_dir / "custom-folder/settings.yml").read_text(), "configuration C"
        )
        # A later deletion recovers the configuration saved during the last successful start.
        shutil.rmtree(self.config_dir / "custom-folder")
        self.helper("restore", revision="101")
        self.assertEqual(
            (self.config_dir / "custom-folder/settings.yml").read_text(), "configuration C"
        )

    def test_remove_without_purge_preserves_configuration(self) -> None:
        """Ordinary removal keeps B, and reverting must leave B unchanged."""
        self.remove(purge=False)
        self.assertEqual(
            (self.config_dir / "custom-folder/settings.yml").read_text(), "configuration B"
        )
        self.helper("restore", revision="101")
        self.assertEqual(
            (self.config_dir / "custom-folder/settings.yml").read_text(), "configuration B"
        )

    def test_reinstall_in_the_purging_revision_does_not_restore_old_configuration(self) -> None:
        """Reinstall in the purging revision does not restore old configuration."""
        self.remove()
        self.plugin("102", "custom-folder")
        self.helper("restore", revision="102")
        self.assertFalse((self.config_dir / "custom-folder").exists())

    def test_a_different_plugin_in_the_same_directory_does_not_get_the_backup(self) -> None:
        """A different plugin in the same directory does not get the backup."""
        self.remove()
        self.plugin("101", "custom-folder", "name=different-plugin\nversion=2.0\n")
        self.helper("restore", revision="101")
        self.assertFalse((self.config_dir / "custom-folder").exists())

    def test_partial_configuration_is_left_untouched(self) -> None:
        """Partial configuration is left untouched."""
        self.remove()
        (self.config_dir / "custom-folder").mkdir()
        self.helper("restore", revision="101")
        self.assertFalse((self.config_dir / "custom-folder/settings.yml").exists())

    def test_failed_removal_keeps_recovery_when_configuration_was_deleted(self) -> None:
        """Failed removal keeps recovery when configuration was deleted."""
        self.remove(exit_code=7)
        self.helper("restore", revision="101")
        self.assertEqual(
            (self.config_dir / "custom-folder/settings.yml").read_text(), "configuration A"
        )

    def test_manual_deletion_after_a_failed_command_restores_saved_configuration(self) -> None:
        """Missing configuration is restored regardless of the earlier failed command."""
        self.helper(
            "run", sys.executable, "-c", "import sys; sys.exit(9)", "remove", expected_exit=9
        )
        shutil.rmtree(self.config_dir / "custom-folder")
        self.helper("restore", revision="101")
        self.assertEqual(
            (self.config_dir / "custom-folder/settings.yml").read_text(), "configuration A"
        )

    def test_failed_purge_does_not_restore_configuration_in_the_purging_revision(self) -> None:
        """Even a failed command may delete config while leaving plugin code in place."""
        self.helper("save", revision="102")
        self.helper(
            "run",
            sys.executable,
            "-c",
            "import shutil,sys; shutil.rmtree(sys.argv[1]); sys.exit(7)",
            str(self.config_dir / "custom-folder"),
            "remove",
            expected_exit=7,
        )
        self.helper("restore", revision="102")
        self.assertFalse((self.config_dir / "custom-folder").exists())
        self.helper("restore", revision="101")
        self.assertEqual(
            (self.config_dir / "custom-folder/settings.yml").read_text(), "configuration A"
        )

    def test_failed_removal_keeps_previously_missing_configuration(self) -> None:
        """A rejected removal must not discard a copy that was already needed for recovery."""
        shutil.rmtree(self.config_dir / "custom-folder")
        self.helper(
            "run",
            sys.executable,
            "-c",
            "import sys; sys.exit(9)",
            "remove",
            revision="101",
            expected_exit=9,
        )
        self.helper("restore", revision="101")
        self.assertEqual(
            (self.config_dir / "custom-folder/settings.yml").read_text(), "configuration A"
        )

    def test_each_retained_revision_can_recover_after_another_purge(self) -> None:
        """Each retained revision can recover after another purge."""
        self.plugin("100", "custom-folder")
        (self.config_dir / "custom-folder/settings.yml").write_text(
            "configuration from revision 100"
        )
        self.helper("save", revision="100")
        (self.config_dir / "custom-folder/settings.yml").write_text("configuration B")
        self.remove()
        self.helper("restore", revision="101")
        shutil.rmtree(self.config_dir / "custom-folder")
        self.helper("restore", revision="100")
        self.assertEqual(
            (self.config_dir / "custom-folder/settings.yml").read_text(),
            "configuration from revision 100",
        )

    def test_repeated_purges_do_not_replace_the_old_revisions_configuration(self) -> None:
        """Repeated purges do not replace the old revisions configuration."""
        self.remove()
        self.plugin("102", "custom-folder")
        self.configuration("custom-folder", "configuration C")
        self.remove()
        self.helper("restore", revision="101")
        self.assertEqual(
            (self.config_dir / "custom-folder/settings.yml").read_text(), "configuration A"
        )

    def test_permissions_and_internal_symlinks_survive(self) -> None:
        """Permissions and internal symlinks survive."""
        config_dir = self.config_dir / "custom-folder"
        (config_dir / "settings.yml").chmod(0o640)
        (config_dir / "alias.yml").symlink_to("settings.yml")
        config_dir.chmod(0o750)
        owner = (config_dir / "settings.yml").stat().st_uid
        self.helper("save", revision="101")
        self.remove()
        self.helper("restore", revision="101")
        self.assertEqual(config_dir.stat().st_mode & 0o777, 0o750)
        self.assertEqual((config_dir / "settings.yml").stat().st_mode & 0o777, 0o640)
        self.assertEqual((config_dir / "settings.yml").stat().st_uid, owner)
        self.assertEqual(os.readlink(config_dir / "alias.yml"), "settings.yml")

    def test_discarding_a_revision_removes_its_recovery_copy(self) -> None:
        """Recovery copies live only in revision data and disappear with that revision."""
        self.remove()
        shutil.rmtree(self.snap_data_root / "101")
        self.helper("restore")
        self.assertFalse((self.config_dir / "custom-folder").exists())
        self.assertFalse((self.snap_data_root / "101").exists())

    def test_no_saved_configuration_means_nothing_is_restored(self) -> None:
        """A revision without its own saved configuration cannot invent a recovery copy."""
        shutil.rmtree(self.snap_data_root / "101")
        self.remove()
        self.plugin("102", "custom-folder")
        self.helper("restore")
        self.assertFalse((self.config_dir / "custom-folder").exists())

    def test_a_broken_config_symlink_is_not_replaced(self) -> None:
        """A broken config symlink is not replaced."""
        self.remove()
        (self.config_dir / "custom-folder").symlink_to("missing-directory")
        self.helper("restore", revision="101")
        self.assertEqual(os.readlink(self.config_dir / "custom-folder"), "missing-directory")

    def test_copied_snapshot_is_not_mistaken_for_a_new_revisions_own_snapshot(self) -> None:
        """Copied snapshot is not mistaken for a new revisions own snapshot."""
        original = self.snap_data_root / "101/usr/share/opensearch/plugin-configuration"
        copied = self.snap_data_root / "100/usr/share/opensearch/plugin-configuration"
        self.plugin("100", "custom-folder")
        shutil.copytree(original, copied, symlinks=True)
        self.remove()
        self.helper("restore", revision="100")
        self.assertFalse((self.config_dir / "custom-folder").exists())

    def test_configuration_edits_are_captured_before_leaving_a_revision(self) -> None:
        """Configuration edits are captured before leaving a revision."""
        (self.config_dir / "custom-folder/settings.yml").write_text("A edited before refresh")
        self.helper("save", revision="101")
        (self.config_dir / "custom-folder/settings.yml").write_text("B after refresh")
        self.remove()
        self.helper("restore", revision="101")
        self.assertEqual(
            (self.config_dir / "custom-folder/settings.yml").read_text(), "A edited before refresh"
        )

    def test_missing_live_config_does_not_erase_an_existing_recovery_copy(self) -> None:
        """Missing live config does not erase an existing recovery copy."""
        self.remove()
        self.helper("save", revision="101")
        self.helper("restore", revision="101")
        self.assertEqual(
            (self.config_dir / "custom-folder/settings.yml").read_text(), "configuration A"
        )

    def test_manual_deletion_restores_saved_configuration(self) -> None:
        """Manual deletion and native purge both recover the target revision's saved copy."""
        shutil.rmtree(self.config_dir / "custom-folder")
        self.helper("restore", revision="101")
        self.assertEqual(
            (self.config_dir / "custom-folder/settings.yml").read_text(), "configuration A"
        )

    def test_failed_snapshot_leaves_the_previous_complete_copy_available(self) -> None:
        """Failed snapshot leaves the previous complete copy available."""
        os.mkfifo(self.config_dir / "custom-folder/unsupported-fifo")
        self.helper("save", revision="101", expected_exit=1)
        (self.config_dir / "custom-folder/unsupported-fifo").unlink()
        self.remove()
        self.helper("restore", revision="101")
        self.assertEqual(
            (self.config_dir / "custom-folder/settings.yml").read_text(), "configuration A"
        )

    def test_interrupted_wrapper_keeps_recovery_and_the_child_holds_the_lock(self) -> None:
        """Interrupted wrapper keeps recovery and the child holds the lock."""
        self.helper("save", revision="102")
        started = self.snap_data_root / "removal-started"
        script = (
            "import pathlib,shutil,sys,time; shutil.rmtree(sys.argv[1]); "
            "pathlib.Path(sys.argv[2]).touch(); time.sleep(1)"
        )
        command = [
            sys.executable,
            str(HELPER),
            "run",
            sys.executable,
            "-c",
            script,
            str(self.config_dir / "custom-folder"),
            str(started),
            "remove",
        ]
        process = subprocess.Popen(
            command, env=self.environment, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        try:
            deadline = time.monotonic() + 5
            while not started.exists() and time.monotonic() < deadline:
                time.sleep(0.01)
            self.assertTrue(started.exists())
            process.kill()
            process.wait()
            before_restore = time.monotonic()
            self.helper("restore", revision="102")
            self.assertGreater(time.monotonic() - before_restore, 0.5)
            self.assertFalse((self.config_dir / "custom-folder").exists())
            self.helper("restore", revision="101")
            self.assertEqual(
                (self.config_dir / "custom-folder/settings.yml").read_text(), "configuration A"
            )
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()

    def test_lock_does_not_require_writing_the_common_root(self) -> None:
        """The shared lock lives in the daemon home, not the root-owned common directory."""
        common_dir = self.snap_data_root / "common"
        common_dir.chmod(0o555)
        try:
            self.remove()
            self.helper("restore", revision="101")
            self.assertEqual(
                (self.config_dir / "custom-folder/settings.yml").read_text(), "configuration A"
            )
        finally:
            common_dir.chmod(0o755)

    def test_manual_deletion_after_interrupted_removal_recovers_each_plugin(self) -> None:
        """Every missing plugin directory gets its own saved copy after an interrupted command."""
        self.plugin("101", "unrelated", "name=unrelated\n")
        self.configuration("unrelated", "unrelated configuration")
        self.helper("save", revision="101")
        started = self.snap_data_root / "interrupted-removal-started"
        script = (
            "import pathlib,shutil,sys,time; shutil.rmtree(sys.argv[1]); "
            "pathlib.Path(sys.argv[2]).touch(); time.sleep(0.3)"
        )
        process = subprocess.Popen(
            [
                sys.executable,
                str(HELPER),
                "run",
                sys.executable,
                "-c",
                script,
                str(self.config_dir / "custom-folder"),
                str(started),
                "remove",
            ],
            env=self.environment,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        try:
            deadline = time.monotonic() + 5
            while not started.exists() and time.monotonic() < deadline:
                time.sleep(0.01)
            self.assertTrue(started.exists())
            process.kill()
            process.wait()
            self.helper("run", sys.executable, "-c", "pass", "list")
            shutil.rmtree(self.config_dir / "unrelated")
            self.helper("restore", revision="101")
            self.assertEqual(
                (self.config_dir / "unrelated/settings.yml").read_text(), "unrelated configuration"
            )
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()

    def test_bundled_descriptor_is_read_from_its_own_retained_snap(self) -> None:
        """Bundled descriptor is read from its own retained snap."""
        snap_root = self.snap_data_root / "snap"
        for revision, version in [("101", "old"), ("102", "new")]:
            bundled = snap_root / revision / "usr/share/opensearch/shipped-plugins/custom-folder"
            bundled.mkdir(parents=True)
            (bundled / "plugin-descriptor.properties").write_text(
                "name=bundled\nversion=" + version
            )
            plugin_dir = (
                self.snap_data_root / revision / "usr/share/opensearch/plugins/custom-folder"
            )
            shutil.rmtree(plugin_dir)
            plugin_dir.symlink_to(
                snap_root / "current/usr/share/opensearch/shipped-plugins/custom-folder"
            )
        (snap_root / "current").symlink_to("101")
        (self.config_dir / "custom-folder/settings.yml").write_text("old bundled configuration")
        self.helper("save", revision="101")
        (snap_root / "current").unlink()
        (snap_root / "current").symlink_to("102")
        (self.config_dir / "custom-folder/settings.yml").write_text("new bundled configuration")
        self.helper(
            "run",
            sys.executable,
            "-c",
            "import shutil,sys; shutil.rmtree(sys.argv[1])",
            str(self.config_dir / "custom-folder"),
            "remove",
        )
        (snap_root / "current").unlink()
        (snap_root / "current").symlink_to("101")
        self.helper("restore", revision="101")
        self.assertEqual(
            (self.config_dir / "custom-folder/settings.yml").read_text(),
            "old bundled configuration",
        )

    def test_manual_deletion_before_refresh_keeps_the_last_recovery_copy(self) -> None:
        """Missing live configuration does not erase the revision's last usable copy."""
        shutil.rmtree(self.config_dir / "custom-folder")
        self.helper("save", revision="101")
        self.configuration("custom-folder", "B created in the new revision")
        self.remove()
        self.helper("restore", revision="101")
        self.assertEqual(
            (self.config_dir / "custom-folder/settings.yml").read_text(), "configuration A"
        )

    def test_custom_directory_names_cannot_collide_with_snapshot_metadata(self) -> None:
        """Custom directory names cannot collide with snapshot metadata."""
        for directory in ["snapshot.json", "snapshot.tmp", "plugins"]:
            with self.subTest(directory=directory):
                self.plugin("101", directory, "name=metadata-name-fixture\n")
                self.configuration(directory, "old configuration for " + directory)
        self.helper("save", revision="101")
        for directory in ["snapshot.json", "snapshot.tmp", "plugins"]:
            with self.subTest(directory=directory):
                self.helper(
                    "run",
                    sys.executable,
                    "-c",
                    "import shutil,sys; shutil.rmtree(sys.argv[1])",
                    str(self.config_dir / directory),
                    "remove",
                )
        self.helper("restore", revision="101")
        for directory in ["snapshot.json", "snapshot.tmp", "plugins"]:
            with self.subTest(directory=directory):
                self.assertEqual(
                    (self.config_dir / directory / "settings.yml").read_text(),
                    "old configuration for " + directory,
                )


if __name__ == "__main__":
    unittest.main()
