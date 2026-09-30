#!/usr/bin/env python3
"""Fails loudly on pyproject.toml/__version__ drift before a build.

Build-time-only, invoked directly by build.sh. See docs/comments-details.md
[20], [124].
"""

from __future__ import annotations

import re
import subprocess
import sys
import tomllib
from pathlib import Path
from typing import Callable

REPO_ROOT = Path(__file__).resolve().parent.parent
# The one branch that gets a plain X.Y.Z version — see [124].
MAIN_BRANCH = "main"

CommandRunner = Callable[[list[str]], "subprocess.CompletedProcess[str]"]


def get_pyproject_version(pyproject_path: Path) -> str:
    data = tomllib.loads(pyproject_path.read_text(encoding="utf-8"))
    return data["project"]["version"]


def get_package_version(repo_root: Path) -> str:
    sys.path.insert(0, str(repo_root / "src"))
    from clientdeck import __version__

    return __version__


def check_versions_match(pyproject_version: str, package_version: str) -> None:
    if pyproject_version != package_version:
        raise SystemExit(
            "version drift: pyproject.toml declares "
            f"{pyproject_version!r} but clientdeck.__version__ is {package_version!r}. "
            "Fix one of them before building — see CLAUDE.md's 'Versioning & changelog'."
        )


def slugify_branch(branch: str) -> str:
    """Branch name -> the PEP 440 local-version segment for it — see [124]."""
    return re.sub(r"[^A-Za-z0-9]+", ".", branch).strip(".")


def _run_git(argv: list[str]) -> "subprocess.CompletedProcess[str]":
    return subprocess.run(argv, capture_output=True, text=True, check=True)


def get_current_branch(repo_root: Path, runner: CommandRunner = _run_git) -> str | None:
    """Best-effort — None (not raised) if it can't be determined, e.g. no
    git on PATH or a detached HEAD — see [124]. `runner` is injectable for
    testing without a real git subprocess."""
    try:
        result = runner(["git", "-C", str(repo_root), "rev-parse", "--abbrev-ref", "HEAD"])
    except (OSError, subprocess.CalledProcessError):
        return None
    branch = result.stdout.strip()
    if not branch or branch == "HEAD":
        return None
    return branch


def check_branch_version(version: str, branch: str) -> None:
    """See [124]: `MAIN_BRANCH` gets a plain X.Y.Z version; every other
    branch's version must carry a `+<slugified-branch-name>` local suffix."""
    base_version, sep, local = version.partition("+")
    if branch == MAIN_BRANCH:
        if sep:
            raise SystemExit(
                f"version drift: on {MAIN_BRANCH!r} but version {version!r} carries a "
                f"branch-local suffix ('+{local}') — see CLAUDE.md's 'Versioning & changelog'."
            )
        return
    expected_local = slugify_branch(branch)
    if not sep or local != expected_local:
        raise SystemExit(
            f"version drift: on branch {branch!r}, version should be "
            f"'{base_version}+{expected_local}' (got {version!r}) — see CLAUDE.md's "
            "'Versioning & changelog'."
        )


def main() -> int:
    pyproject_version = get_pyproject_version(REPO_ROOT / "pyproject.toml")
    package_version = get_package_version(REPO_ROOT)
    check_versions_match(pyproject_version, package_version)
    branch = get_current_branch(REPO_ROOT)
    if branch is not None:
        check_branch_version(pyproject_version, branch)
    print(pyproject_version)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
