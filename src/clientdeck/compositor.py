"""Runtime desktop-compositor detection and KWin's real backdrop blur.

Making the desktop *behind* a translucent window actually blurry (not
just alpha-transparent, which is all plain QML/Qt Quick can do on its own)
is a compositor-specific window-manager hint — there is no cross-desktop
Qt/QML API for it:

- KWin (KDE Plasma, X11) supports it directly via a documented X11
  property, `_KDE_NET_WM_BLUR_BEHIND_REGION`, set on the app's own window.
- Mutter (GNOME) has no equivalent per-app hint at all — real blur there
  would need a GNOME Shell extension (a desktop-level install, not
  something this app can do from inside itself), so the existing
  alpha-transparency-only glass look is the best available fallback.
- Wayland KWin uses a completely different mechanism (the
  `org_kde_kwin_blur` Wayland protocol extension) — not implemented here;
  everything in this module is X11-only (guard with
  `QGuiApplication.platformName() == "xcb"` before calling in).

Detection queries the *actually running* window manager via the
ICCCM/EWMH-standard `_NET_SUPPORTING_WM_CHECK` mechanism (something any
compliant X11 WM must implement to identify itself), rather than trusting
environment variables like `XDG_CURRENT_DESKTOP` — those describe the
logged-in session, which can be stale, absent, or simply wrong about
what's actually compositing right now.

Everything here is best-effort: any failure (no X11, `Xlib` unavailable,
a WM that doesn't implement EWMH, a property-set that fails) just means
detection/blur silently does nothing — never raises, never blocks
startup. See CLAUDE.md's environment constraints: none of this is
verifiable by the agent (no real X server/compositor in the sandbox), so
it's written to be safe to call blind and needs manual, on-host
verification against a real KWin session.
"""

from __future__ import annotations

from typing import Callable

_NET_SUPPORTING_WM_CHECK = "_NET_SUPPORTING_WM_CHECK"
_NET_WM_NAME = "_NET_WM_NAME"
_UTF8_STRING = "UTF8_STRING"
_KDE_BLUR_BEHIND_REGION = "_KDE_NET_WM_BLUR_BEHIND_REGION"

DisplayFactory = Callable[[], object]


def is_kwin(wm_name: str | None) -> bool:
    """True if a detected window-manager name identifies KWin — the only
    compositor this module knows a real per-app blur-behind hint for."""
    return wm_name is not None and wm_name.strip().lower() == "kwin"


def detect_window_manager_name(display_factory: DisplayFactory | None = None) -> str | None:
    """The actually-running X11 window manager's self-reported name, or
    None if it can't be determined (no X11, no Xlib, non-EWMH WM, etc.).

    `display_factory` is injectable for testing without a real X server —
    defaults to `Xlib.display.Display`.
    """
    try:
        if display_factory is None:
            from Xlib.display import Display

            display_factory = Display
        d = display_factory()
        try:
            root = d.screen().root
            wm_check_atom = d.intern_atom(_NET_SUPPORTING_WM_CHECK)
            name_atom = d.intern_atom(_NET_WM_NAME)
            utf8_atom = d.intern_atom(_UTF8_STRING)

            check_prop = root.get_full_property(wm_check_atom, 0)
            if not check_prop or not check_prop.value:
                return None
            wm_window_id = check_prop.value[0]
            wm_window = d.create_resource_object("window", wm_window_id)

            name_prop = wm_window.get_full_property(name_atom, utf8_atom)
            if not name_prop or not name_prop.value:
                return None
            value = name_prop.value
            if isinstance(value, bytes):
                return value.decode("utf-8", errors="replace")
            return str(value)
        finally:
            d.close()
    except Exception:
        return None


def set_kwin_blur_behind(window_id: int, display_factory: DisplayFactory | None = None) -> bool:
    """Ask KWin to blur whatever is behind the X11 window `window_id`.

    Sets `_KDE_NET_WM_BLUR_BEHIND_REGION` to an empty region, which means
    "blur the whole window" per KWin's convention. Returns whether it was
    applied; never raises.
    """
    try:
        from Xlib import X, Xatom

        if display_factory is None:
            from Xlib.display import Display

            display_factory = Display
        d = display_factory()
        try:
            window = d.create_resource_object("window", window_id)
            blur_atom = d.intern_atom(_KDE_BLUR_BEHIND_REGION)
            window.change_property(blur_atom, Xatom.CARDINAL, 32, [], mode=X.PropModeReplace)
            d.flush()
            return True
        finally:
            d.close()
    except Exception:
        return False


def enable_blur_behind_if_supported(window_id: int, display_factory: DisplayFactory | None = None) -> bool:
    """Best-effort: if the actually-running WM is KWin, ask it to blur
    behind `window_id`. Returns whether it was applied — False everywhere
    else (e.g. GNOME/Mutter), where the window's existing alpha-transparent
    glass look (see Main.qml/Theme.qml) is the fallback.
    """
    if not is_kwin(detect_window_manager_name(display_factory)):
        return False
    return set_kwin_blur_behind(window_id, display_factory)
