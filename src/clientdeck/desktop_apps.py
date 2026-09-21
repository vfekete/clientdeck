"""Discovery of local and system-wide `.desktop` launcher shortcuts.

Used by the "add app for a client" dialog to list existing registered
applications the user can pick from, per the freedesktop.org Desktop Entry
Specification's search-path and override rules.
"""

from __future__ import annotations

import configparser
import os
import re
from dataclasses import dataclass
from pathlib import Path

_FIELD_CODE_RE = re.compile(r"%[fFuUdDnNickvm%]")


@dataclass(frozen=True)
class DesktopApp:
    name: str
    exec_command: str
    icon: str | None
    working_dir: str | None
    source_path: str


def _default_search_dirs() -> list[str]:
    """Ordered lowest-priority first, so later entries can override earlier
    ones on filename collision, matching the spec's precedence rule (user
    data dir wins over system dirs; earlier XDG_DATA_DIRS entries win over
    later ones)."""
    xdg_data_dirs = os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share")
    system_dirs = [f"{d.rstrip('/')}/applications" for d in reversed(xdg_data_dirs.split(":")) if d]
    xdg_data_home = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local/share")
    home_dir = f"{xdg_data_home.rstrip('/')}/applications"
    return [*system_dirs, home_dir]


def _strip_field_codes(exec_line: str) -> str:
    return _FIELD_CODE_RE.sub("", exec_line).strip()


def _parse_desktop_file(path: Path) -> DesktopApp | None:
    parser = configparser.RawConfigParser(strict=False)
    parser.optionxform = str  # type: ignore[assignment]  # keys are case-sensitive
    try:
        parser.read(path, encoding="utf-8")
    except (OSError, configparser.Error):
        return None
    if "Desktop Entry" not in parser:
        return None
    section = parser["Desktop Entry"]
    # Required key, no lenient default — see [14].
    if section.get("Type") != "Application":
        return None
    if section.get("NoDisplay", "false").strip().lower() == "true":
        return None
    if section.get("Hidden", "false").strip().lower() == "true":
        return None
    name = section.get("Name")
    exec_line = section.get("Exec")
    if not name or not exec_line:
        return None
    return DesktopApp(
        name=name,
        exec_command=_strip_field_codes(exec_line),
        icon=section.get("Icon") or None,
        working_dir=section.get("Path") or None,
        source_path=str(path),
    )


def discover_desktop_apps(search_dirs: list[str] | None = None) -> list[DesktopApp]:
    """Scan (in override-precedence order) for user-visible `.desktop` apps.

    When the same `.desktop` filename appears in more than one directory,
    the one from the higher-priority directory (later in `search_dirs`, per
    `_default_search_dirs`'s ordering contract) wins.
    """
    dirs = search_dirs if search_dirs is not None else _default_search_dirs()
    by_filename: dict[str, DesktopApp] = {}
    for directory in dirs:
        dir_path = Path(directory)
        if not dir_path.is_dir():
            continue
        for entry in sorted(dir_path.glob("*.desktop")):
            app = _parse_desktop_file(entry)
            if app is not None:
                by_filename[entry.name] = app
    return sorted(by_filename.values(), key=lambda a: a.name.lower())
