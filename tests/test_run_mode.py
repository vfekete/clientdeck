from __future__ import annotations

from clientdeck.run_mode import is_real_mode, script_mode_args


def test_unset_is_mock():
    assert is_real_mode(False, {}) is False


def test_real_is_real_case_insensitive():
    assert is_real_mode(False, {"CLIENTDECK_MODE": "real"}) is True
    assert is_real_mode(False, {"CLIENTDECK_MODE": " REAL "}) is True


def test_anything_else_is_mock():
    for value in ("mock", "", "1", "true", "reall"):
        assert is_real_mode(False, {"CLIENTDECK_MODE": value}) is False


def test_script_mode_args():
    assert script_mode_args(True) == ["--real"]
    assert script_mode_args(False) == []


def test_packaged_build_is_always_real_whatever_the_env():
    assert is_real_mode(True, {}) is True
    assert is_real_mode(True, {"CLIENTDECK_MODE": "mock"}) is True
