#!/usr/bin/env python3
"""Helpers to set the initial passwords of the internal users."""
import os
import sys
import tempfile

from argparse import ArgumentParser, Namespace

import yaml


def parse_args() -> Namespace:
    parser = ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)

    set_hash = commands.add_parser("set-hash", help="set the password hash of a user")
    set_hash.add_argument("-f", "--file", required=True, help="internal_users.yml path")
    set_hash.add_argument("-u", "--user", required=True, help="name of the user")
    set_hash.add_argument("--hash", required=True, help="hash of the password")

    return parser.parse_args()


def set_hash(path: str, user: str, password_hash: str) -> None:
    with open(path) as f:
        internal_users = yaml.safe_load(f)

    if not isinstance(internal_users, dict) or not isinstance(internal_users.get(user), dict):
        sys.exit(f"ERROR: no user {user} in {path}")

    internal_users[user]["hash"] = password_hash

    # Written next to the file, then moved over it with the same permissions:
    # a failure leaves the original file untouched
    stat = os.stat(path)
    fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(path))
    try:
        with os.fdopen(fd, "w") as f:
            yaml.safe_dump(internal_users, f, sort_keys=False)
        os.chmod(tmp_path, stat.st_mode)
        os.chown(tmp_path, stat.st_uid, stat.st_gid)
        os.replace(tmp_path, path)
    except BaseException:
        os.unlink(tmp_path)
        raise


if __name__ == "__main__":
    args = parse_args()

    if args.command == "set-hash":
        set_hash(args.file, args.user, args.hash)
    else:
        sys.exit(f"unknown command {args.command}")
