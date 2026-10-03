#!/usr/bin/env python3
"""Keep a revision's plugin configuration available when that revision returns."""

import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time


class PluginConfiguration:
    """Save plugin directories with their revision and restore only missing directories."""

    def __init__(self) -> None:
        """Locate this revision's plugins, saved configuration and shared command lock."""
        revision_dir = Path(os.environ["SNAP_DATA"])
        self.revision = revision_dir.name
        self.plugins_dir = revision_dir / "usr/share/opensearch/plugins"
        self.config_dir = Path(os.environ["OPENSEARCH_PATH_CONF"])
        self.snapshots_dir = revision_dir / "usr/share/opensearch/plugin-configuration"
        self.pending_removal = self.snapshots_dir / "removal-in-progress"
        self.lock_path = (
            Path(os.environ["SNAP_COMMON"]) / "home/snap_daemon/.plugin-configuration.lock"
        )

    def read_snapshot(self) -> tuple[Path, dict[str, str]]:
        """Read our saved copy, rejecting snapshots copied forward from another revision."""
        snapshot_dir = self.snapshots_dir / "current"
        metadata = snapshot_dir / "snapshot.json"
        # A new revision may have no snapshot yet, or inherit its predecessor's copy.
        if not metadata.is_file():
            return snapshot_dir, {}
        record = json.loads(metadata.read_text())
        return snapshot_dir, record["plugins"] if record["revision"] == self.revision else {}

    def installed_plugins(self) -> dict[str, str]:
        """Identify installed plugins by physical directory and descriptor contents."""
        # Read only the active revision: its bundled links already point at its own snap.
        return {
            descriptor.parent.name: hashlib.sha256(descriptor.read_bytes()).hexdigest()
            for descriptor in self.plugins_dir.glob("*/plugin-descriptor.properties")
        }

    def save_snapshot(self, removed_directories: frozenset[str] = frozenset()) -> None:
        """Save installed plugins' configuration without changing the live directories.

        Keep the last usable copy when a directory is missing. After a native
        removal, discard its deleted copies so this revision cannot undo its own purge.
        """
        previous_snapshot, previous_plugins = self.read_snapshot()
        self.snapshots_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
        pending_dir = Path(tempfile.mkdtemp(prefix="pending-", dir=self.snapshots_dir))
        (pending_dir / "plugins").mkdir()
        saved_plugins = {}
        # Use physical directory names, including custom.foldername, just as the native installer does.
        for directory_name, descriptor_hash in self.installed_plugins().items():
            source = self.config_dir / directory_name
            # Retain a missing directory's last copy only while the same plugin is installed.
            if (
                directory_name not in removed_directories
                and not os.path.lexists(source)
                and previous_plugins.get(directory_name) == descriptor_hash
            ):
                source = previous_snapshot / "plugins" / directory_name
            # Core settings, certificates and the keystore are outside these plugin directories.
            if source.is_dir():
                shutil.copytree(source, pending_dir / "plugins" / directory_name, symlinks=True)
                saved_plugins[directory_name] = descriptor_hash
        (pending_dir / "snapshot.json").write_text(
            json.dumps({"revision": self.revision, "plugins": saved_plugins})
        )
        self.publish_snapshot(pending_dir)

    def publish_snapshot(self, pending_dir: Path) -> None:
        """Switch to a completed copy atomically, then discard superseded snapshots."""
        completed_dir = self.snapshots_dir / f"saved-{time.time_ns()}"
        pending_dir.rename(completed_dir)
        next_link = self.snapshots_dir / "next"
        # An interrupted publication may have left a temporary link behind.
        if next_link.is_symlink():
            next_link.unlink()
        next_link.symlink_to(completed_dir.name)
        next_link.replace(self.snapshots_dir / "current")
        # Do not delete the previous copy until the complete replacement is selected.
        for snapshot_dir in self.snapshots_dir.iterdir():
            # Failed copies can also be discarded now that a complete copy exists.
            if snapshot_dir != completed_dir and snapshot_dir.name.startswith(
                ("saved-", "pending-")
            ):
                shutil.rmtree(snapshot_dir)

    def restore_missing(self) -> None:
        """Restore missing configuration for matching plugins, regardless of why it disappeared."""
        snapshot_dir, saved_plugins = self.read_snapshot()
        # A different plugin occupying the same directory must not inherit an old plugin's settings.
        for directory_name, descriptor_hash in self.installed_plugins().items():
            destination = self.config_dir / directory_name
            # Keep existing directories, including empty ones and broken symlinks, exactly as they are.
            if saved_plugins.get(directory_name) != descriptor_hash or os.path.lexists(destination):
                continue
            # Expose the restored directory only after its whole contents have been copied.
            with tempfile.TemporaryDirectory(
                prefix=".plugin-restore-", dir=self.config_dir
            ) as staging:
                staged_config = Path(staging) / "config"
                shutil.copytree(
                    snapshot_dir / "plugins" / directory_name, staged_config, symlinks=True
                )
                staged_config.rename(destination)
            print(
                f"Restored {directory_name} configuration from revision {self.revision}",
                file=sys.stderr,
            )

    def finish_removal(self) -> None:
        """Update this revision's snapshot after removal, including interrupted commands."""
        # Discard only copies whose live directories disappeared during this command.
        # Unrelated directories that were already missing still need their saved copies.
        removed_directories = frozenset(
            name
            for name in json.loads(self.pending_removal.read_text())
            if not os.path.lexists(self.config_dir / name)
        )
        self.save_snapshot(removed_directories)
        self.pending_removal.unlink()

    def run_command(self, command: list[str], lock_fd: int) -> int:
        """Run the native plugin tool and reflect removals in this revision's saved copy."""
        is_removal = "remove" in command[1:]
        # Leave one marker so the next invocation can finish bookkeeping if this wrapper is killed.
        if is_removal:
            self.snapshots_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
            present_directories = [
                name for name in self.installed_plugins() if os.path.lexists(self.config_dir / name)
            ]
            temporary_record = self.pending_removal.with_suffix(".tmp")
            temporary_record.write_text(json.dumps(present_directories))
            temporary_record.replace(self.pending_removal)
        exit_code = subprocess.call(command, pass_fds=(lock_fd,))
        # Native option parsing and removal stay in OpenSearch; we only save the resulting state.
        if is_removal:
            self.finish_removal()
        return exit_code if exit_code >= 0 else 128 - exit_code

    def execute(self, mode: str, command: list[str]) -> int:
        """Prevent snapshots and plugin commands from observing one another half-finished."""
        # The daemon home is writable by snap_daemon; the root of SNAP_COMMON is not.
        # The native child inherits the lock so killing its wrapper cannot release it early.
        with self.lock_path.open("a") as lock_file:
            fcntl.flock(lock_file, fcntl.LOCK_EX)
            # Reconcile an interrupted removal before allowing this revision to restore anything.
            if self.pending_removal.exists():
                self.finish_removal()
            # Restore before saving: saving first could discard the only remaining recovery copy.
            if mode == "restore":
                self.restore_missing()
            # Lifecycle hooks save configuration; plugin commands manage their own completion.
            if mode in ("save", "restore"):
                self.save_snapshot()
                return 0
            return self.run_command(command, lock_file.fileno())


def main(arguments: list[str]) -> int:
    """Validate wrapper arguments and report failures without printing configuration contents."""
    # Only snap wrappers call this helper; reject incomplete invocations clearly.
    try:
        mode, *command = arguments
        if mode not in ("save", "restore", "run") or (mode == "run" and not command):
            raise ValueError(
                "Usage: plugin-configuration.py save | restore | run COMMAND [ARGUMENTS...]"
            )
        return PluginConfiguration().execute(mode, command)
    except (OSError, ValueError, IndexError) as error:
        print(f"Plugin configuration recovery failed: {error}", file=sys.stderr)
        return 1


# Importing the helper must not run a command or alter configuration.
if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
