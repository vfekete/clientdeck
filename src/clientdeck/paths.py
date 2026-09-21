"""Resolves the app's own bundled directories (QML, launch scripts) —
source checkout vs. packaged single-file executable.

See docs/comments-details.md [16].
"""

from __future__ import annotations

import builtins
import sys
from pathlib import Path


def is_packaged_build() -> bool:
    """True when running as the compiled Nuitka onefile binary, False for a
    plain source checkout (e.g. via run.sh/`uv run python -m clientdeck`).
    Used beyond just path resolution — see [17]."""
    return getattr(sys.modules.get("__main__"), "__compiled__", None) is not None


def get_packaged_root_dir() -> Path | None:
    """The onefile extraction directory, or None when running from source.
    See [18]."""
    if not is_packaged_build():
        return None
    binary_dir = getattr(builtins, "__nuitka_binary_dir", None)
    if binary_dir:
        return Path(binary_dir)
    return Path(sys.executable).resolve().parent


def get_qml_dir() -> Path:
    root = get_packaged_root_dir()
    if root is not None:
        return root / "qml"
    return Path(__file__).resolve().parent / "qml"


def get_scripts_dir() -> Path:
    root = get_packaged_root_dir()
    if root is not None:
        return root / "scripts"
    return Path(__file__).resolve().parent.parent / "scripts"


def get_loader_path() -> Path:
    """Path to the compiled clientdeck-loader splash binary — see [16].
    Caller checks `.is_file()`; the dev-mode path only exists once
    `make -C src/loader` has actually been run locally."""
    root = get_packaged_root_dir()
    if root is not None:
        return root / "clientdeck-loader"
    return Path(__file__).resolve().parent.parent / "loader" / "build" / "clientdeck-loader"
