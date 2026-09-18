from __future__ import annotations

import os
import subprocess

import pytest

from tests.conftest import load_script_module

create_user = load_script_module("create_user")


class _FakeCompletedProcess:
    def __init__(self, returncode: int):
        self.returncode = returncode


def test_build_useradd_command():
    assert create_user.build_useradd_command("acme") == ["useradd", "--create-home", "--user-group", "acme"]


def test_refuses_when_not_root(monkeypatch):
    monkeypatch.setattr(os, "geteuid", lambda: 1000)
    exit_code = create_user.run("acme")
    assert exit_code == create_user.EXIT_NOT_ROOT


def test_creates_user_when_root(monkeypatch):
    monkeypatch.setattr(create_user, "MOCK_MODE", False)
    monkeypatch.setattr(os, "geteuid", lambda: 0)
    calls = []

    def fake_run(cmd):
        calls.append(list(cmd))
        return _FakeCompletedProcess(0)

    monkeypatch.setattr(subprocess, "run", fake_run)

    exit_code = create_user.run("acme")

    assert exit_code == 0
    assert calls == [["useradd", "--create-home", "--user-group", "acme"]]


def test_useradd_failure_propagates_exit_code(monkeypatch):
    monkeypatch.setattr(create_user, "MOCK_MODE", False)
    monkeypatch.setattr(os, "geteuid", lambda: 0)
    monkeypatch.setattr(subprocess, "run", lambda cmd: _FakeCompletedProcess(1))

    exit_code = create_user.run("acme")

    assert exit_code == create_user.EXIT_USERADD_FAILED


def test_mock_mode_is_on_by_default():
    assert create_user.MOCK_MODE is True


def test_mock_mode_never_touches_subprocess_even_as_root(monkeypatch):
    monkeypatch.setattr(os, "geteuid", lambda: 0)
    monkeypatch.setattr(subprocess, "run", lambda *a, **k: (_ for _ in ()).throw(AssertionError("should not run")))

    exit_code = create_user.run("acme")

    assert exit_code == 0


def test_mock_mode_prints_the_command_it_would_run(monkeypatch, capsys):
    monkeypatch.setattr(os, "geteuid", lambda: 0)

    create_user.run("acme")

    output = capsys.readouterr().out
    assert "useradd --create-home --user-group acme" in output


def test_mock_mode_still_requires_root(monkeypatch):
    monkeypatch.setattr(os, "geteuid", lambda: 1000)

    exit_code = create_user.run("acme")

    assert exit_code == create_user.EXIT_NOT_ROOT


def test_parse_args_requires_username():
    with pytest.raises(SystemExit):
        create_user.parse_args([])


def test_parse_args_happy_path():
    args = create_user.parse_args(["acme"])
    assert args.username == "acme"
