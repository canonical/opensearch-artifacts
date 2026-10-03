"""Exercise YAML setting edits with the packaged yq and real Bash helpers."""

import itertools
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
YQ = Path(os.environ.get("SNAP", "/missing-snap")) / "usr/bin/yq"


@unittest.skipUnless(YQ.is_file(), "Run with SNAP set to the installed snap, which provides yq")
class SettingTests(unittest.TestCase):
    """Check effective setting removal and preservation of unrelated YAML values."""

    def setUp(self) -> None:
        """Keep fixtures and logs separate from the running node's configuration."""
        temporary = tempfile.TemporaryDirectory(dir=os.environ.get("SNAP_COMMON"))
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.config = self.root / "opensearch.yml"
        self.environment = dict(os.environ, OPS_ROOT=str(SCRIPTS),
                                OPENSEARCH_PATH_CONF=str(self.root),
                                SNAP_LOG_DIR=str(self.root / "logs"))

    def write(self, document: dict) -> None:
        """Write JSON, a YAML subset, preserving the test's key order."""
        self.config.write_text(json.dumps(document))

    def read(self) -> dict:
        """Read actual yq output without needing a separate test YAML dependency."""
        result = subprocess.run([str(YQ), "-c", ".", str(self.config)],
                                env=self.environment, text=True, capture_output=True, check=True)
        return json.loads(result.stdout)

    def edit(self, operation: str, key: str, *values: str) -> None:
        """Call the production helper with real files and shell-safe arguments."""
        subprocess.run(["bash", "-eu", "-c", 'source "$1"; shift; "$@"', "test",
                        str(SCRIPTS / "helpers/set-conf.sh"), operation, str(self.config),
                        key, *values], env=self.environment, text=True, capture_output=True,
                       check=True)

    def test_remove_dotted_and_nested_values_preserves_siblings(self) -> None:
        """Deleting a dotted override must not expose the earlier nested setting."""
        self.write({"cluster": {"name": "old", "routing": {"allocation": "keep"}},
                    "cluster.name": "new", "cluster.name_suffix": "also keep"})
        self.edit("remove_yaml_prop", "cluster.name")
        self.assertEqual(self.read(), {"cluster": {"routing": {"allocation": "keep"}},
                                       "cluster.name_suffix": "also keep"})

    def test_read_uses_last_representation_and_handles_missing_values(self) -> None:
        """TLS key lookup must use the effective path, including mixed YAML spellings."""
        flat = ("plugins.security.ssl.http.pemkey_filepath", "flat-key.pem")
        nested = ("plugins.security", {"ssl": {"http.pemkey_filepath": "nested-key.pem"}})
        for entries, expected in (([flat, nested], "nested-key.pem"),
                                  ([nested, flat], "flat-key.pem"), ([], "")):
            with self.subTest(entries=entries):
                self.write(dict(entries))
                result = subprocess.run(
                    ["bash", "-eu", "-c", 'source "$1"; get_yaml_prop "$2" "$3"',
                     "test", str(SCRIPTS / "helpers/set-conf.sh"), str(self.config),
                     "plugins.security.ssl.http.pemkey_filepath"],
                    env=self.environment, text=True, capture_output=True, check=True)
                self.assertEqual(result.stdout.strip(), expected)

    def test_remove_every_mixed_spelling_of_tls_password(self) -> None:
        """Every split between nested and dotted mapping keys denotes the same setting."""
        parts = ["plugins", "security", "ssl", "http", "pemkey_password"]
        for boundaries in itertools.product((False, True), repeat=len(parts) - 1):
            keys = [parts[0]]
            for split, part in zip(boundaries, parts[1:]):
                if split:
                    keys.append(part)
                else:
                    keys[-1] += "." + part
            document = {keys[-1]: "old-password", "unrelated": "keep"}
            for key in reversed(keys[:-1]):
                document = {key: document, "sibling": "keep"}
            with self.subTest(keys=keys):
                self.write(document)
                self.edit("remove_yaml_prop", ".".join(parts))
                expected = document
                for key in keys[:-1]:
                    expected = expected[key]
                del expected[keys[-1]]
                self.assertEqual(self.read(), document)

    def test_setting_string_removes_old_representation_in_either_order(self) -> None:
        """A nested key later in the file must not override a newly written value."""
        items = [("cluster.name", "dotted-old"), ("cluster", {"name": "nested-old"})]
        for entries in (items, list(reversed(items))):
            with self.subTest(entries=entries):
                self.write(dict(entries))
                self.edit("set_yaml_prop", "cluster.name", "001,a=b")
                self.assertEqual(self.read(), {"cluster": {}, "cluster.name": "001,a=b"})

    def test_lists_and_empty_lists_replace_nested_values(self) -> None:
        """Typed list setters preserve strings containing commas and support empty lists."""
        for value in ('["CN=a,OU=x", "CN=b,OU=x"]', "[]"):
            with self.subTest(value=value):
                self.write({"plugins.security": {"nodes_dn": ["old"], "disabled": False}})
                self.edit("set_yaml_prop_json", "plugins.security.nodes_dn", value)
                self.assertEqual(self.read(), {"plugins.security": {"disabled": False},
                                               "plugins.security.nodes_dn": json.loads(value)})

    def test_append_preserves_effective_list_and_deduplicates(self) -> None:
        """Append uses the last YAML representation, as the native settings loader does."""
        cases = [
            ({"nodes_dn": ["CN=old,OU=x"]}, ["CN=old,OU=x", "CN=new,OU=x"]),
            ({"nodes_dn": "CN=old,OU=x"}, ["CN=old,OU=x", "CN=new,OU=x"]),
            ({"nodes_dn": []}, ["CN=new,OU=x"]),
        ]
        for nested, expected in cases:
            with self.subTest(nested=nested):
                self.write({"plugins.security.nodes_dn": ["overridden"],
                            "plugins.security": dict(nested, disabled=False)})
                self.edit("add_yaml_list_item", "plugins.security.nodes_dn", "CN=new,OU=x")
                self.edit("add_yaml_list_item", "plugins.security.nodes_dn", "CN=new,OU=x")
                self.assertEqual(self.read(), {"plugins.security": {"disabled": False},
                                               "plugins.security.nodes_dn": expected})

    def test_absent_key_does_not_change_siblings_or_array_elements(self) -> None:
        """Array indexes are not nested setting names, and prefix matches are not removals."""
        document = {"node": {"roles": ["data", "ingest"]},
                    "node.roles_extra": "keep", "node.roles.01": "keep"}
        self.write(document)
        self.edit("remove_yaml_prop", "node.roles.0")
        self.assertEqual(self.read(), document)
        self.edit("remove_yaml_prop", "missing.path")
        self.assertEqual(self.read(), document)

    def test_tls_list_setter_replaces_all_old_admin_dns(self) -> None:
        """The TLS initializer's list helper keeps complete comma-containing DNs."""
        self.write({"plugins.security.authcz.admin_dn": ["old-flat"],
                    "plugins": {"security.authcz": {"admin_dn": ["old-nested"],
                                                    "unrelated": "keep"}}})
        self.edit("set_yaml_list", "plugins.security.authcz.admin_dn",
                  "CN=admin1,OU=x", "CN=admin2,OU=x")
        self.assertEqual(self.read(), {
            "plugins": {"security.authcz": {"unrelated": "keep"}},
            "plugins.security.authcz.admin_dn": ["CN=admin1,OU=x", "CN=admin2,OU=x"]})

    def test_public_setup_set_then_remove_does_not_restore_old_value(self) -> None:
        """The real setup wrapper must not revive a value when its override is removed."""
        self.write({"cluster": {"name": "nested-before", "max_shards_per_node": 1000}})
        for argument in ("-Ecluster.name=nested-after", "-Ecluster.name="):
            subprocess.run(["bash", str(SCRIPTS / "wrappers/setup.sh"), argument],
                           env=self.environment, text=True, capture_output=True, check=True)
        self.assertEqual(self.read(), {"cluster": {"max_shards_per_node": 1000}})


if __name__ == "__main__":
    unittest.main()
