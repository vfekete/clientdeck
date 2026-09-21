#!/usr/bin/env python3
"""Impersonate a client's Linux user and run a command in their context.

Wraps `su - <username> -c '<command>'`, and — for GUI apps — grants X access
via `xhost +SI:localhost:<username>` before launching and revokes it again
with `xhost -SI:localhost:<username>` once the child process exits, however
it exits (clean exit, non-zero exit, or this script being killed/crashing),
so the X access grant is never leaked.

argv contract:
    launch_as_user.py --username USER [--workdir DIR] [--gui] COMMAND [ARGS...]

Exit code: the launched command's own exit code, or a small fixed non-zero
code if `su` itself could not be started at all (e.g. not installed).

MOCK_MODE: see docs/comments-details.md [19].
"""

from __future__ import annotations

import argparse
import shlex
import subprocess
import sys

EXIT_SU_NOT_FOUND = 127

MOCK_MODE = True


def build_su_command(username: str, command: list[str], workdir: str | None) -> list[str]:
    inner = " ".join(shlex.quote(part) for part in command)
    if workdir:
        inner = f"cd {shlex.quote(workdir)} && {inner}"
    return ["su", "-", username, "-c", inner]


def build_xhost_grant_command(username: str) -> list[str]:
    return ["xhost", f"+SI:localhost:{username}"]


def build_xhost_revoke_command(username: str) -> list[str]:
    return ["xhost", f"-SI:localhost:{username}"]


def _run_best_effort(cmd: list[str]) -> None:
    """Run a command, swallowing any failure (missing binary, non-zero
    exit). Used for the xhost grant/revoke calls, which must never be able
    to prevent the actual launch or mask its exit code."""
    try:
        subprocess.run(cmd, check=False)
    except OSError:
        pass


def run(username: str, command: list[str], workdir: str | None, gui: bool) -> int:
    if MOCK_MODE:
        if gui:
            print(f"[MOCK] launch_as_user.py: would run: {' '.join(build_xhost_grant_command(username))}")
        print(f"[MOCK] launch_as_user.py: would run: {' '.join(build_su_command(username, command, workdir))}")
        if gui:
            print(f"[MOCK] launch_as_user.py: would run: {' '.join(build_xhost_revoke_command(username))}")
        return 0
    if gui:
        _run_best_effort(build_xhost_grant_command(username))
    try:
        try:
            result = subprocess.run(build_su_command(username, command, workdir))
        except OSError as exc:
            print(f"launch_as_user: failed to run su: {exc}", file=sys.stderr)
            return EXIT_SU_NOT_FOUND
        return result.returncode
    finally:
        if gui:
            _run_best_effort(build_xhost_revoke_command(username))


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Launch a command as another user, impersonating a ClientDeck client."
    )
    parser.add_argument("--username", required=True, help="Linux username to impersonate")
    parser.add_argument("--workdir", default=None, help="Working directory for the launched command")
    parser.add_argument(
        "--gui",
        action="store_true",
        help="Grant/revoke X access via xhost around the launch (for GUI apps)",
    )
    parser.add_argument("command", nargs=argparse.REMAINDER, help="Command (and args) to run as the user")
    args = parser.parse_args(argv)
    if not args.command:
        parser.error("no command given to launch")
    return args


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    return run(args.username, args.command, args.workdir, args.gui)


if __name__ == "__main__":
    raise SystemExit(main())
