#!/usr/bin/env python3
"""Helpers to set the initial passwords of the internal users."""
import sys

from argparse import ArgumentParser, Namespace

import yaml


def parse_args() -> Namespace:
    parser = ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)

    users = commands.add_parser("users", help="list the internal users")
    users.add_argument("-f", "--file", required=True, help="internal_users.yml path")

    set_hash = commands.add_parser("set-hash", help="set the password hash of a user")
    set_hash.add_argument("-f", "--file", required=True, help="internal_users.yml path")
    set_hash.add_argument("-u", "--user", required=True, help="name of the user")
    set_hash.add_argument("--hash", required=True, help="hash of the password")

    return parser.parse_args()


def users(path: str) -> list:
    with open(path) as f:
        return [user for user in yaml.safe_load(f) if user != "_meta"]


def set_hash(path: str, user: str, password_hash: str) -> None:
    with open(path) as f:
        internal_users = yaml.safe_load(f)

    internal_users[user]["hash"] = password_hash

    with open(path, "w") as f:
        yaml.safe_dump(internal_users, f, sort_keys=False)


if __name__ == "__main__":
    args = parse_args()

    if args.command == "users":
        print("\n".join(users(args.file)))
    elif args.command == "set-hash":
        set_hash(args.file, args.user, args.hash)
    else:
        sys.exit(f"unknown command {args.command}")
