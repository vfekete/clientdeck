from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from types import ModuleType

import pytest
from PySide6.QtCore import QCoreApplication

REPO_ROOT = Path(__file__).resolve().parent.parent
SCRIPTS_DIR = REPO_ROOT / "src" / "scripts"
TOOLS_DIR = REPO_ROOT / "tools"


@pytest.fixture(scope="session", autouse=True)
def qt_app():
    """Some Qt model machinery (signals/roleNames) wants a QCoreApplication
    instance to exist, even for headless unit tests with no display."""
    app = QCoreApplication.instance()
    if app is None:
        app = QCoreApplication([])
    yield app


def _load_module_from_path(name: str, path: Path) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def load_script_module(name: str) -> ModuleType:
    """Import one of the standalone `src/scripts/*.py` files as a module.

    They're deliberately not part of the `clientdeck` package (see
    CLAUDE.md: independently runnable, own argv/exit-code contract), so they
    need loading by file path rather than a normal import.
    """
    return _load_module_from_path(name, SCRIPTS_DIR / f"{name}.py")


def load_tool_module(name: str) -> ModuleType:
    """Import one of the standalone `tools/*.py` build-support scripts."""
    return _load_module_from_path(name, TOOLS_DIR / f"{name}.py")
