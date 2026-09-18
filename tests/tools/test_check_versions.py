from __future__ import annotations

import pytest

from tests.conftest import load_tool_module

check_versions = load_tool_module("check_versions")


def test_matching_versions_do_not_raise():
    check_versions.check_versions_match("1.2.3", "1.2.3")


def test_drifted_versions_raise_systemexit_with_both_versions_named():
    with pytest.raises(SystemExit) as exc_info:
        check_versions.check_versions_match("1.2.3", "1.2.4")
    message = str(exc_info.value)
    assert "1.2.3" in message
    assert "1.2.4" in message


def test_get_pyproject_version_reads_project_table(tmp_path):
    pyproject = tmp_path / "pyproject.toml"
    pyproject.write_text('[project]\nname = "demo"\nversion = "9.9.9"\n', encoding="utf-8")

    assert check_versions.get_pyproject_version(pyproject) == "9.9.9"


def test_real_repo_versions_currently_match():
    """Guards against exactly the drift this tool exists to catch."""
    version = check_versions.get_pyproject_version(check_versions.REPO_ROOT / "pyproject.toml")
    package_version = check_versions.get_package_version(check_versions.REPO_ROOT)
    check_versions.check_versions_match(version, package_version)
