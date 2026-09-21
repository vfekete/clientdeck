#!/usr/bin/env python3
"""Create a new Linux user (with matching group and home dir) for a
ClientDeck client.

Intended to be invoked with root privileges via `pkexec` as part of the "add
client" flow (see CLAUDE.md's "Privilege escalation" section) — this script
itself does not invoke pkexec, it's the target of it.

argv contract:
    create_user.py USERNAME

Exit codes:
    0   user created
    1   not running as root
    2   the useradd invocation failed (see stderr)

MOCK_MODE: see docs/comments-details.md [19].
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys

EXIT_NOT_ROOT = 1
EXIT_USERADD_FAILED = 2

MOCK_MODE = True


def build_useradd_command(username: str) -> list[str]:
    return ["useradd", "--create-home", "--user-group", username]


def run(username: str) -> int:
    if os.geteuid() != 0:
        print("create_user.py must be run as root (e.g. via pkexec).", file=sys.stderr)
        return EXIT_NOT_ROOT
    command = build_useradd_command(username)
    if MOCK_MODE:
        print(f"[MOCK] create_user.py: would run: {' '.join(command)}")
        return 0
    result = subprocess.run(command)
    if result.returncode != 0:
        return EXIT_USERADD_FAILED
    return 0


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create a Linux user/group for a new ClientDeck client.")
    parser.add_argument("username")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    return run(args.username)


if __name__ == "__main__":
    raise SystemExit(main())
