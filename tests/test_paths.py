from __future__ import annotations

import builtins
import sys
from pathlib import Path
from types import SimpleNamespace

from clientdeck import paths


def test_source_checkout_qml_dir_is_package_qml_folder():
    assert paths.get_qml_dir() == Path(paths.__file__).resolve().parent / "qml"


def test_source_checkout_scripts_dir_is_sibling_of_src(monkeypatch):
    assert paths.get_scripts_dir() == Path(paths.__file__).resolve().parent.parent / "scripts"


def test_is_packaged_build_is_false_from_source():
    assert paths.is_packaged_build() is False


def test_is_packaged_build_is_true_when_compiled(monkeypatch):
    monkeypatch.setattr(sys.modules["__main__"], "__compiled__", SimpleNamespace(), raising=False)

    assert paths.is_packaged_build() is True


def test_get_packaged_root_dir_is_none_outside_a_compiled_build():
    assert paths.get_packaged_root_dir() is None


def test_packaged_root_dir_uses_nuitka_binary_dir_hint(monkeypatch, tmp_path):
    monkeypatch.setattr(sys.modules["__main__"], "__compiled__", SimpleNamespace(), raising=False)
    monkeypatch.setattr(builtins, "__nuitka_binary_dir", str(tmp_path), raising=False)

    assert paths.get_packaged_root_dir() == tmp_path


def test_packaged_root_dir_falls_back_to_executable_dir(monkeypatch):
    monkeypatch.setattr(sys.modules["__main__"], "__compiled__", SimpleNamespace(), raising=False)
    monkeypatch.delattr(builtins, "__nuitka_binary_dir", raising=False)

    assert paths.get_packaged_root_dir() == Path(sys.executable).resolve().parent


def test_packaged_qml_and_scripts_dirs_are_siblings_of_root(monkeypatch, tmp_path):
    monkeypatch.setattr(sys.modules["__main__"], "__compiled__", SimpleNamespace(), raising=False)
    monkeypatch.setattr(builtins, "__nuitka_binary_dir", str(tmp_path), raising=False)

    assert paths.get_qml_dir() == tmp_path / "qml"
    assert paths.get_scripts_dir() == tmp_path / "scripts"
