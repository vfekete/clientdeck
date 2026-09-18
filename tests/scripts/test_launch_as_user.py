from __future__ import annotations

import subprocess

import pytest

from tests.conftest import load_script_module

launch_as_user = load_script_module("launch_as_user")


class _FakeCompletedProcess:
    def __init__(self, returncode: int):
        self.returncode = returncode


@pytest.fixture
def real_mode(monkeypatch):
    """Disables MOCK_MODE for tests exercising the real su/xhost behavior
    that only runs once UI/UX prototyping is over (see the module
    docstring)."""
    monkeypatch.setattr(launch_as_user, "MOCK_MODE", False)


@pytest.fixture
def recorded_calls(monkeypatch, real_mode):
    calls: list[list[str]] = []
    exit_codes: dict[str, int] = {"su": 0}

    def fake_run(cmd, check=False):
        calls.append(list(cmd))
        code = exit_codes.get(cmd[0], 0)
        return _FakeCompletedProcess(code)

    monkeypatch.setattr(subprocess, "run", fake_run)
    return calls, exit_codes


def test_build_su_command_quotes_and_joins():
    cmd = launch_as_user.build_su_command("acme", ["code", "--new-window"], workdir=None)
    assert cmd == ["su", "-", "acme", "-c", "code --new-window"]


def test_build_su_command_includes_cd_for_workdir():
    cmd = launch_as_user.build_su_command("acme", ["ls"], workdir="/home/acme/project")
    assert cmd == ["su", "-", "acme", "-c", "cd /home/acme/project && ls"]


def test_build_xhost_grant_and_revoke_commands():
    assert launch_as_user.build_xhost_grant_command("acme") == ["xhost", "+SI:localhost:acme"]
    assert launch_as_user.build_xhost_revoke_command("acme") == ["xhost", "-SI:localhost:acme"]


def test_gui_run_grants_then_launches_then_revokes(recorded_calls):
    calls, _ = recorded_calls
    exit_code = launch_as_user.run("acme", ["code"], workdir=None, gui=True)

    assert exit_code == 0
    assert calls == [
        ["xhost", "+SI:localhost:acme"],
        ["su", "-", "acme", "-c", "code"],
        ["xhost", "-SI:localhost:acme"],
    ]


def test_non_gui_run_never_calls_xhost(recorded_calls):
    calls, _ = recorded_calls
    launch_as_user.run("acme", ["ls"], workdir=None, gui=False)

    assert all(c[0] != "xhost" for c in calls)


def test_xhost_revoked_even_if_su_exits_nonzero(recorded_calls):
    calls, exit_codes = recorded_calls
    exit_codes["su"] = 42

    exit_code = launch_as_user.run("acme", ["code"], workdir=None, gui=True)

    assert exit_code == 42
    assert calls[-1] == ["xhost", "-SI:localhost:acme"]


def test_xhost_revoked_even_if_su_raises(monkeypatch, real_mode):
    calls: list[list[str]] = []

    def fake_run(cmd, check=False):
        calls.append(list(cmd))
        if cmd[0] == "su":
            raise OSError("su not found")
        return _FakeCompletedProcess(0)

    monkeypatch.setattr(subprocess, "run", fake_run)

    exit_code = launch_as_user.run("acme", ["code"], workdir=None, gui=True)

    assert exit_code == launch_as_user.EXIT_SU_NOT_FOUND
    assert calls == [
        ["xhost", "+SI:localhost:acme"],
        ["su", "-", "acme", "-c", "code"],
        ["xhost", "-SI:localhost:acme"],
    ]


def test_mock_mode_is_on_by_default():
    assert launch_as_user.MOCK_MODE is True


def test_mock_mode_never_touches_subprocess(monkeypatch):
    monkeypatch.setattr(subprocess, "run", lambda *a, **k: (_ for _ in ()).throw(AssertionError("should not run")))

    exit_code = launch_as_user.run("acme", ["code"], workdir=None, gui=True)

    assert exit_code == 0


def test_mock_mode_prints_the_commands_it_would_run(capsys):
    launch_as_user.run("acme", ["code"], workdir=None, gui=True)

    output = capsys.readouterr().out
    assert "xhost +SI:localhost:acme" in output
    assert "su - acme -c code" in output
    assert "xhost -SI:localhost:acme" in output


def test_mock_mode_non_gui_skips_xhost_lines(capsys):
    launch_as_user.run("acme", ["ls"], workdir=None, gui=False)

    output = capsys.readouterr().out
    assert "xhost" not in output


def test_parse_args_requires_a_command():
    with pytest.raises(SystemExit):
        launch_as_user.parse_args(["--username", "acme"])


def test_parse_args_happy_path():
    args = launch_as_user.parse_args(["--username", "acme", "--gui", "code", "--new-window"])
    assert args.username == "acme"
    assert args.gui is True
    assert args.command == ["code", "--new-window"]
