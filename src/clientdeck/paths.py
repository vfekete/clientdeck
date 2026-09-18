"""Resolves the app's own bundled directories (QML, launch scripts) —
source checkout vs. packaged single-file executable.

See `claude-blocks/python-single-app-instance.claude.md`'s "Gotchas": a path
built relative to `__file__`/the original repo layout is correct when
running from source, but breaks once packaged (Nuitka onefile
self-extracts to a temp directory with a different layout). This module is
the one place that distinction lives, so the rest of the app never has to
think about it.

Actual bundling (see `build.sh` / `pysidedeploy.spec`):
- `qml/` is auto-bundled by `pyside6-deploy` as a data dir sitting right
  next to the compiled binary's extraction root, i.e. `<root>/qml`.
- `src/scripts/` is *not* auto-detected (it's a sibling of the package, not
  a subdirectory of it), so `build.sh` bundles it explicitly via Nuitka's
  `--include-data-dir`, landing at `<root>/scripts`.
"""

from __future__ import annotations

import builtins
import sys
from pathlib import Path


def is_packaged_build() -> bool:
    """True when running as the compiled Nuitka onefile binary, False for a
    plain source checkout (e.g. via run.sh/`uv run python -m clientdeck`).

    Used beyond just path resolution — e.g. app.py only installs its
    Ctrl+C/SIGINT handler in source mode, since it's not confirmed to work
    correctly against the packaged binary's two-process (bootstrap +
    extracted payload) structure yet.
    """
    return getattr(sys.modules.get("__main__"), "__compiled__", None) is not None


def get_packaged_root_dir() -> Path | None:
    """The onefile extraction directory, or None when running from source.

    Nuitka onefile injects `__nuitka_binary_dir` into `builtins` at runtime
    (see the packaging blueprint) pointing at that directory; fall back to
    the running executable's own directory if that hint isn't present.
    """
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
