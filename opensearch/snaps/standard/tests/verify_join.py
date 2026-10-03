#!/usr/bin/env python3
"""Verify the README's join procedure against two live TLS-enabled nodes.

Run after provisioning a trusted admin certificate and following the joining
procedure. This test only reads cluster state and an optional existing document.
Repeat it after restarting, refreshing or reverting the joining snap.
"""

import argparse
import json
from pathlib import Path
import ssl
from typing import Any
import urllib.request


def api(url: str, path: str, context: ssl.SSLContext) -> dict[str, Any]:
    """Read an API response with CA and hostname verification enabled."""
    with urllib.request.urlopen(url.rstrip("/") + path, context=context, timeout=45) as response:
        return json.load(response)


def main() -> None:
    """Check cluster identity, healthy membership and optional document preservation."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", required=True, help="Existing node's HTTPS URL")
    parser.add_argument("--joining", required=True, help="Joining node's HTTPS URL")
    parser.add_argument("--ca", required=True, type=Path)
    parser.add_argument("--cert", required=True, type=Path, help="Authorized admin certificate")
    parser.add_argument("--key", required=True, type=Path, help="Unencrypted admin private key")
    parser.add_argument("--nodes", type=int, default=2)
    parser.add_argument("--document", help="Existing document path, e.g. /join-canary/_doc/1")
    options = parser.parse_args()
    if options.nodes < 2 or not all(
        url.startswith("https://") for url in (options.target, options.joining)
    ):
        parser.error("Use HTTPS URLs and expect at least two nodes")

    context = ssl.create_default_context(cafile=str(options.ca))
    context.load_cert_chain(str(options.cert), str(options.key))
    target = api(options.target, "/", context)
    joining = api(options.joining, "/", context)
    assert target["cluster_uuid"] not in ("_na_", ""), target
    assert joining["cluster_uuid"] == target["cluster_uuid"], (target, joining)
    assert joining["cluster_name"] == target["cluster_name"], (target, joining)
    assert joining["name"] != target["name"], "URLs must identify two different nodes"

    for url in (options.target, options.joining):
        health = api(url, "/_cluster/health?wait_for_status=green&timeout=30s", context)
        assert not health["timed_out"] and health["status"] == "green", health
        assert health["number_of_nodes"] == options.nodes, health
        members = api(url, "/_nodes", context)["nodes"]
        names = {node["name"] for node in members.values()}
        assert {target["name"], joining["name"]} <= names, names

    if options.document:
        original = api(options.target, options.document, context)
        through_joiner = api(options.joining, options.document, context)
        assert original["found"] and through_joiner["found"], (original, through_joiner)
        assert original["_source"] == through_joiner["_source"], (original, through_joiner)

    print(json.dumps({"cluster_uuid": target["cluster_uuid"], "nodes": options.nodes,
                      "status": "green", "document_verified": bool(options.document)}))


if __name__ == "__main__":
    main()
