from __future__ import annotations

from PySide6.QtGui import QIcon

from clientdeck import icon_provider


def test_ensure_icon_theme_configured_adds_standard_paths(monkeypatch):
    monkeypatch.setattr(QIcon, "themeSearchPaths", staticmethod(lambda: [":/icons"]))
    monkeypatch.setattr(QIcon, "themeName", staticmethod(lambda: ""))
    recorded = {}
    monkeypatch.setattr(QIcon, "setThemeSearchPaths", staticmethod(lambda paths: recorded.__setitem__("paths", paths)))
    monkeypatch.setattr(QIcon, "setThemeName", staticmethod(lambda name: recorded.__setitem__("name", name)))

    icon_provider.ensure_icon_theme_configured()

    assert recorded["paths"][0] == ":/icons"
    assert "/usr/share/icons" in recorded["paths"]
    assert "/usr/local/share/icons" in recorded["paths"]
    assert recorded["name"] == "hicolor"


def test_ensure_icon_theme_configured_does_not_duplicate_existing_paths(monkeypatch):
    monkeypatch.setattr(QIcon, "themeSearchPaths", staticmethod(lambda: [":/icons", "/usr/share/icons"]))
    monkeypatch.setattr(QIcon, "themeName", staticmethod(lambda: "breeze"))
    recorded = {}
    monkeypatch.setattr(QIcon, "setThemeSearchPaths", staticmethod(lambda paths: recorded.__setitem__("paths", paths)))
    monkeypatch.setattr(QIcon, "setThemeName", staticmethod(lambda name: recorded.__setitem__("name", name)))

    icon_provider.ensure_icon_theme_configured()

    assert recorded["paths"].count("/usr/share/icons") == 1


def test_ensure_icon_theme_configured_preserves_already_detected_theme_name(monkeypatch):
    monkeypatch.setattr(QIcon, "themeSearchPaths", staticmethod(lambda: []))
    monkeypatch.setattr(QIcon, "themeName", staticmethod(lambda: "breeze"))
    monkeypatch.setattr(QIcon, "setThemeSearchPaths", staticmethod(lambda paths: None))

    name_calls = []
    monkeypatch.setattr(QIcon, "setThemeName", staticmethod(lambda name: name_calls.append(name)))

    icon_provider.ensure_icon_theme_configured()

    assert name_calls == []


class _FakeRequestedSize:
    def __init__(self, valid: bool):
        self._valid = valid

    def isValid(self):
        return self._valid


class _FakePixmap:
    def __init__(self, w, h, null=False):
        self._w = w
        self._h = h
        self._null = null

    def width(self):
        return self._w

    def height(self):
        return self._h

    def isNull(self):
        return self._null


class _FakeIcon:
    def __init__(self, size, null=False):
        self._size = size
        self._null = null

    def pixmap(self, size):
        assert size is self._size
        return _FakePixmap(0, 0, null=True) if self._null else _FakePixmap(48, 48)


def test_resolve_theme_pixmap_uses_default_size_when_requested_size_invalid(monkeypatch):
    requested = _FakeRequestedSize(valid=False)
    monkeypatch.setattr(
        icon_provider.QIcon, "fromTheme", staticmethod(lambda name: _FakeIcon(icon_provider.DEFAULT_ICON_SIZE))
    )

    result = icon_provider.resolve_theme_pixmap("some-icon", requested)

    assert result.width() == 48


def test_resolve_theme_pixmap_uses_requested_size_when_valid(monkeypatch):
    requested = _FakeRequestedSize(valid=True)
    monkeypatch.setattr(icon_provider.QIcon, "fromTheme", staticmethod(lambda name: _FakeIcon(requested)))

    result = icon_provider.resolve_theme_pixmap("some-icon", requested)

    assert result.width() == 48


def test_resolve_theme_pixmap_falls_back_to_pixmaps_dir(monkeypatch, tmp_path):
    requested = _FakeRequestedSize(valid=True)
    monkeypatch.setattr(icon_provider.QIcon, "fromTheme", staticmethod(lambda name: _FakeIcon(requested, null=True)))
    monkeypatch.setattr(icon_provider, "PIXMAPS_DIR", tmp_path)
    (tmp_path / "gummi.png").write_bytes(b"")

    calls = []

    def fake_load(path, size):
        calls.append(path)
        return _FakePixmap(48, 48)

    monkeypatch.setattr(icon_provider, "_load_pixmap_from_path", fake_load)

    result = icon_provider.resolve_theme_pixmap("gummi", requested)

    assert calls == [tmp_path / "gummi.png"]
    assert result.width() == 48


def test_resolve_theme_pixmap_returns_null_when_nothing_found_anywhere(monkeypatch, tmp_path):
    requested = _FakeRequestedSize(valid=True)
    monkeypatch.setattr(icon_provider.QIcon, "fromTheme", staticmethod(lambda name: _FakeIcon(requested, null=True)))
    monkeypatch.setattr(icon_provider, "PIXMAPS_DIR", tmp_path)  # empty directory — no match

    result = icon_provider.resolve_theme_pixmap("does-not-exist-anywhere", requested)

    assert result.isNull() is True


def test_resolve_theme_pixmap_prefers_theme_result_when_not_null(monkeypatch, tmp_path):
    requested = _FakeRequestedSize(valid=True)
    monkeypatch.setattr(icon_provider.QIcon, "fromTheme", staticmethod(lambda name: _FakeIcon(requested, null=False)))
    monkeypatch.setattr(icon_provider, "PIXMAPS_DIR", tmp_path)
    (tmp_path / "some-icon.png").write_bytes(b"")

    monkeypatch.setattr(
        icon_provider, "_load_pixmap_from_path", lambda *a: (_ for _ in ()).throw(AssertionError("should not run"))
    )

    result = icon_provider.resolve_theme_pixmap("some-icon", requested)

    assert result.width() == 48
