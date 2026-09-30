from __future__ import annotations

import subprocess

import pytest

from tests.conftest import load_tool_module

check_versions = load_tool_module("check_versions")


def _fake_runner(stdout: str):
    def runner(argv):
        return subprocess.CompletedProcess(argv, 0, stdout=stdout, stderr="")

    return runner


def _raising_runner(exc: Exception):
    def runner(argv):
        raise exc

    return runner


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


def test_real_repo_branch_version_is_consistent():
    """Guards against exactly the per-branch drift [124] exists to catch."""
    version = check_versions.get_pyproject_version(check_versions.REPO_ROOT / "pyproject.toml")
    branch = check_versions.get_current_branch(check_versions.REPO_ROOT)
    assert branch is not None, "expected a real git branch while running the test suite"
    check_versions.check_branch_version(version, branch)


@pytest.mark.parametrize(
    ("branch", "expected"),
    [
        ("feat/properties", "feat.properties"),
        ("feat//weird--name__here", "feat.weird.name.here"),
        ("main", "main"),
        ("-leading-and-trailing-", "leading.and.trailing"),
    ],
)
def test_slugify_branch(branch, expected):
    assert check_versions.slugify_branch(branch) == expected


def test_check_branch_version_accepts_plain_version_on_main_branch():
    check_versions.check_branch_version("1.2.3", "main")


def test_check_branch_version_rejects_local_suffix_on_main_branch():
    with pytest.raises(SystemExit) as exc_info:
        check_versions.check_branch_version("1.2.3+feat.properties", "main")
    assert "main" in str(exc_info.value)


def test_check_branch_version_accepts_matching_suffix_on_other_branch():
    check_versions.check_branch_version("0.1.0+feat.properties", "feat/properties")


def test_check_branch_version_rejects_missing_suffix_on_other_branch():
    with pytest.raises(SystemExit) as exc_info:
        check_versions.check_branch_version("0.1.0", "feat/properties")
    assert "feat/properties" in str(exc_info.value)
    assert "0.1.0+feat.properties" in str(exc_info.value)


def test_check_branch_version_rejects_mismatched_suffix_on_other_branch():
    with pytest.raises(SystemExit):
        check_versions.check_branch_version("0.1.0+some.other.branch", "feat/properties")


def test_get_current_branch_returns_branch_name():
    runner = _fake_runner("feat/properties\n")
    assert check_versions.get_current_branch(check_versions.REPO_ROOT, runner=runner) == "feat/properties"


def test_get_current_branch_returns_none_for_detached_head():
    runner = _fake_runner("HEAD\n")
    assert check_versions.get_current_branch(check_versions.REPO_ROOT, runner=runner) is None


def test_get_current_branch_returns_none_when_git_unavailable():
    runner = _raising_runner(FileNotFoundError("git not found"))
    assert check_versions.get_current_branch(check_versions.REPO_ROOT, runner=runner) is None


def test_get_current_branch_returns_none_when_git_fails():
    runner = _raising_runner(subprocess.CalledProcessError(128, ["git"]))
    assert check_versions.get_current_branch(check_versions.REPO_ROOT, runner=runner) is None
