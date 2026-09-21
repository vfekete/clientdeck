"""Resolves `image://theme/<name>` QML image sources to the desktop's
current icon theme.

See docs/comments-details.md [15] for why this module exists and the
theme-search-path/pixmap-fallback quirks it works around.
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
