"""Resolves `image://theme/<name>` QML image sources to the desktop's
current icon theme.

Qt does not register a "theme" image provider automatically for a plain
`QGuiApplication` + `QQmlApplicationEngine` app — confirmed missing on a
real host: Qt logged `Invalid image provider: image://theme/<name>` for
every discovered `.desktop` app whose `Icon=` value was a theme name
rather than an absolute path (which is the common case; see
`desktop_apps.py`). `QIcon.fromTheme()` implements the freedesktop icon
theme spec on Linux and works fine under `QGuiApplication` — it needs no
widgets — so a small `QQuickImageProvider` wrapping it is enough to make
`image://theme/<name>` resolve, once the provider itself is registered.

That alone wasn't sufficient, though: `QIcon.themeSearchPaths()` defaults
to just `[":/icons"]` (a Qt *resource* path, always empty for an app that
doesn't bundle icons into a .qrc) — real filesystem directories like
`/usr/share/icons` are only added by Qt's own platform-theme integration,
which isn't guaranteed to run (confirmed empty under the `offscreen` QPA
platform used for this project's own headless testing, and not something
to assume works for every real desktop session either). `ensure_icon_theme_configured()`
adds the standard XDG icon directories unconditionally, and falls back to
the universal "hicolor" theme name only if nothing was already detected
— confirmed this combination resolves real icon names (including the
exact ones reported missing: "gsmartcontrol", "gwenview", "granatier")
that otherwise came back null.

One further gap confirmed by that same testing: some apps (e.g. "gummi")
only ship an icon in `/usr/share/pixmaps/<name>.<ext>` — the legacy
freedesktop fallback location, outside the theme-directory hierarchy
entirely — and `QIcon.fromTheme()` does not check it. `resolve_theme_pixmap()`
falls back to it directly when the theme lookup comes back empty.
"""

from __future__ import annotations

from pathlib import Path

from PySide6.QtCore import QSize
from PySide6.QtGui import QIcon, QPixmap
from PySide6.QtQuick import QQuickImageProvider

DEFAULT_ICON_SIZE = QSize(48, 48)

_STANDARD_ICON_SEARCH_PATHS = (
    "/usr/share/icons",
    "/usr/local/share/icons",
)
_STANDARD_ICON_SEARCH_HOME_SUBDIRS = (
    ".local/share/icons",
    ".icons",
)
_FALLBACK_THEME_NAME = "hicolor"

PIXMAPS_DIR = Path("/usr/share/pixmaps")
_PIXMAP_EXTENSIONS = (".png", ".xpm", ".svg")


def ensure_icon_theme_configured() -> None:
    """Best-effort, additive setup: never removes/overrides anything Qt's
    own platform integration may have already gotten right, only fills in
    what's missing."""
    home = Path.home()
    candidate_paths = [*_STANDARD_ICON_SEARCH_PATHS, *(str(home / sub) for sub in _STANDARD_ICON_SEARCH_HOME_SUBDIRS)]
    existing_paths = QIcon.themeSearchPaths()
    QIcon.setThemeSearchPaths(existing_paths + [p for p in candidate_paths if p not in existing_paths])

    if not QIcon.themeName():
        QIcon.setThemeName(_FALLBACK_THEME_NAME)


def _load_pixmap_from_path(path: Path, size: QSize) -> QPixmap:
    return QIcon(str(path)).pixmap(size)


def resolve_theme_pixmap(name: str, requested_size: QSize) -> QPixmap:
    """The actual lookup, factored out of `ThemeIconProvider` so it's
    testable as a plain function — constructing a real
    `QQuickImageProvider` needs a QPA platform, which pytest doesn't have
    to hand."""
    target_size = requested_size if requested_size.isValid() else DEFAULT_ICON_SIZE
    pixmap = QIcon.fromTheme(name).pixmap(target_size)
    if pixmap.isNull():
        for ext in _PIXMAP_EXTENSIONS:
            candidate = PIXMAPS_DIR / f"{name}{ext}"
            if candidate.is_file():
                fallback = _load_pixmap_from_path(candidate, target_size)
                if not fallback.isNull():
                    return fallback
    return pixmap


class ThemeIconProvider(QQuickImageProvider):
    def __init__(self) -> None:
        super().__init__(QQuickImageProvider.ImageType.Pixmap)

    def requestPixmap(self, id: str, size: QSize, requestedSize: QSize) -> QPixmap:
        pixmap = resolve_theme_pixmap(id, requestedSize)
        size.setWidth(pixmap.width())
        size.setHeight(pixmap.height())
        return pixmap
