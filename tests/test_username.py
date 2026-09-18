from __future__ import annotations

import grp
import pwd

from clientdeck.username import username_or_group_exists


class _FakeEntry:
    pass


def test_empty_name_is_not_taken():
    assert username_or_group_exists("") is False


def test_existing_user_is_taken(monkeypatch):
    monkeypatch.setattr(pwd, "getpwnam", lambda name: _FakeEntry())
    monkeypatch.setattr(grp, "getgrnam", lambda name: (_ for _ in ()).throw(KeyError(name)))
    assert username_or_group_exists("alice") is True


def test_existing_group_is_taken(monkeypatch):
    monkeypatch.setattr(pwd, "getpwnam", lambda name: (_ for _ in ()).throw(KeyError(name)))
    monkeypatch.setattr(grp, "getgrnam", lambda name: _FakeEntry())
    assert username_or_group_exists("developers") is True


def test_unknown_name_is_available(monkeypatch):
    monkeypatch.setattr(pwd, "getpwnam", lambda name: (_ for _ in ()).throw(KeyError(name)))
    monkeypatch.setattr(grp, "getgrnam", lambda name: (_ for _ in ()).throw(KeyError(name)))
    assert username_or_group_exists("brand-new-client") is False
