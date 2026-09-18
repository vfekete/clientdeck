#!/usr/bin/env python3
"""Delete a Linux user (and their home dir) that a ClientDeck client used to
be provisioned as.

Invoked when a client is renamed and the user chooses, in the "delete
original content?" prompt, to remove the old account's content rather than
keep it orphaned on disk. Intended to be invoked with root privileges via
`pkexec`, same as create_user.py — this script itself does not invoke
pkexec, it's the target of it.

argv contract:
    delete_user.py USERNAME

Exit codes:
    0   user deleted
    1   not running as root
    2   the userdel invocation failed (see stderr)

MOCK_MODE: the app is currently in UI/UX-prototyping phase — this script
does not actually delete a Linux user. It still requires root (so the real
pkexec authentication dialog can be exercised), but the userdel step itself
is replaced with a printed line saying what would have run. Flip MOCK_MODE
to False once prototyping is done and real user deletion should happen.
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys

EXIT_NOT_ROOT = 1
EXIT_USERDEL_FAILED = 2

MOCK_MODE = True


def build_userdel_command(username: str) -> list[str]:
    # --remove also deletes the home dir and mail spool, matching "delete
    # the original content" rather than just the account entry itself.
    return ["userdel", "--remove", username]


def run(username: str) -> int:
    if os.geteuid() != 0:
        print("delete_user.py must be run as root (e.g. via pkexec).", file=sys.stderr)
        return EXIT_NOT_ROOT
    command = build_userdel_command(username)
    if MOCK_MODE:
        print(f"[MOCK] delete_user.py: would run: {' '.join(command)}")
        return 0
    result = subprocess.run(command)
    if result.returncode != 0:
        return EXIT_USERDEL_FAILED
    return 0


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Delete a Linux user/home dir for a renamed ClientDeck client.")
    parser.add_argument("username")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    return run(args.username)


if __name__ == "__main__":
    raise SystemExit(main())
