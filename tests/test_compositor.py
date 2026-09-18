from __future__ import annotations

from clientdeck import compositor


def test_is_kwin_matches_case_and_whitespace_insensitively():
    assert compositor.is_kwin("KWin") is True
    assert compositor.is_kwin("kwin") is True
    assert compositor.is_kwin("  KWin  ") is True


def test_is_kwin_rejects_other_names():
    assert compositor.is_kwin("Mutter") is False
    assert compositor.is_kwin("GNOME Shell") is False
    assert compositor.is_kwin("") is False
    assert compositor.is_kwin(None) is False


class _FakeProperty:
    def __init__(self, value):
        self.value = value


class _FakeWindow:
    def __init__(self, name_prop=None, change_property_calls=None):
        self._name_prop = name_prop
        self._change_property_calls = change_property_calls if change_property_calls is not None else []

    def get_full_property(self, atom, prop_type):
        return self._name_prop

    def change_property(self, atom, prop_type, prop_format, data, mode):
        self._change_property_calls.append((atom, prop_type, prop_format, data, mode))


class _FakeScreen:
    def __init__(self, root):
        self.root = root


class _FakeDisplay:
    """Simulates just enough of Xlib.display.Display's surface for
    detect_window_manager_name()/set_kwin_blur_behind() to exercise their
    real logic without a real X server."""

    def __init__(self, wm_name: str | bytes | None = "KWin", wm_check_present: bool = True):
        self.closed = False
        self._atom_counter = 1000
        self._wm_window = _FakeWindow(name_prop=_FakeProperty(wm_name) if wm_name is not None else None)
        root_prop = _FakeProperty([self._wm_window]) if wm_check_present else None
        self._root = _FakeWindow()
        self._root_check_prop = root_prop
        self._screen = _FakeScreen(self._root)
        self.change_property_calls: list = []

    def screen(self):
        return self._screen

    def intern_atom(self, name):
        self._atom_counter += 1
        return self._atom_counter

    def create_resource_object(self, kind, window_id):
        assert kind == "window"
        if window_id is self._wm_window:
            return self._wm_window
        # For set_kwin_blur_behind, window_id is an arbitrary int; return a
        # fresh window object wired to this display's shared call list.
        return _FakeWindow(change_property_calls=self.change_property_calls)

    def flush(self):
        pass

    def close(self):
        self.closed = True

    # get_full_property is looked up on `root`, not the display, in real
    # Xlib — patch it here for the "wm check" query specifically.
    def _install_root_property(self):
        original = self._root.get_full_property

        def get_full_property(atom, prop_type):
            return self._root_check_prop

        self._root.get_full_property = get_full_property
        return original


def _make_display_factory(**kwargs):
    def factory():
        d = _FakeDisplay(**kwargs)
        d._install_root_property()
        return d

    return factory


def test_detect_window_manager_name_returns_kwin():
    factory = _make_display_factory(wm_name="KWin")
    assert compositor.detect_window_manager_name(display_factory=factory) == "KWin"


def test_detect_window_manager_name_decodes_bytes():
    factory = _make_display_factory(wm_name=b"Mutter")
    assert compositor.detect_window_manager_name(display_factory=factory) == "Mutter"


def test_detect_window_manager_name_none_when_no_wm_check_property():
    factory = _make_display_factory(wm_check_present=False)
    assert compositor.detect_window_manager_name(display_factory=factory) is None


def test_detect_window_manager_name_none_when_name_property_missing():
    factory = _make_display_factory(wm_name=None)
    assert compositor.detect_window_manager_name(display_factory=factory) is None


def test_detect_window_manager_name_none_on_any_exception():
    def factory():
        raise OSError("no X11 display")

    assert compositor.detect_window_manager_name(display_factory=factory) is None


def test_detect_window_manager_name_closes_display_even_on_success():
    holder = {}

    def factory():
        d = _FakeDisplay(wm_name="KWin")
        d._install_root_property()
        holder["display"] = d
        return d

    compositor.detect_window_manager_name(display_factory=factory)
    assert holder["display"].closed is True


def test_set_kwin_blur_behind_sets_cardinal_property():
    factory = _make_display_factory()
    result = compositor.set_kwin_blur_behind(12345, display_factory=factory)
    assert result is True


def test_set_kwin_blur_behind_false_on_exception():
    def factory():
        raise OSError("no X11 display")

    assert compositor.set_kwin_blur_behind(12345, display_factory=factory) is False


def test_enable_blur_behind_applies_only_for_kwin(monkeypatch):
    monkeypatch.setattr(compositor, "detect_window_manager_name", lambda display_factory=None: "KWin")
    calls = []
    monkeypatch.setattr(
        compositor, "set_kwin_blur_behind", lambda window_id, display_factory=None: calls.append(window_id) or True
    )

    result = compositor.enable_blur_behind_if_supported(999)

    assert result is True
    assert calls == [999]


def test_enable_blur_behind_skips_non_kwin(monkeypatch):
    monkeypatch.setattr(compositor, "detect_window_manager_name", lambda display_factory=None: "Mutter")
    monkeypatch.setattr(
        compositor, "set_kwin_blur_behind", lambda *a, **k: (_ for _ in ()).throw(AssertionError("should not run"))
    )

    assert compositor.enable_blur_behind_if_supported(999) is False


def test_enable_blur_behind_skips_when_wm_undetectable(monkeypatch):
    monkeypatch.setattr(compositor, "detect_window_manager_name", lambda display_factory=None: None)

    assert compositor.enable_blur_behind_if_supported(999) is False
