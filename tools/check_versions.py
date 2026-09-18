#!/usr/bin/env python3
"""Fails loudly on version drift before a build, per the packaging
blueprint's Step 2 (`claude-blocks/python-single-app-instance.claude.md`):
`pyproject.toml`'s `[project].version` and `clientdeck.__version__` must
always agree — a packaged binary that misreports its own version is a real,
easy-to-miss bug class.

Not part of the `clientdeck` package itself (it's a build-time-only
concern, kept out of what actually gets shipped) — invoked directly by
`build.sh`. On success, prints the version to stdout so the caller can
capture it for naming the output binary.
"""

from __future__ import annotations

import sys
import tomllib
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent


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


def main() -> int:
    pyproject_version = get_pyproject_version(REPO_ROOT / "pyproject.toml")
    package_version = get_package_version(REPO_ROOT)
    check_versions_match(pyproject_version, package_version)
    print(pyproject_version)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
