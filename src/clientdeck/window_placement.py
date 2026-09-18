"""Pure logic for deciding where to place the main window on startup.

Kept free of any real QScreen/QWindow calls so the "restore on the saved
monitor, else center on the first available one" decision can be unit
tested without a display.
"""

from __future__ import annotations

from dataclasses import dataclass

from .config import WindowState


@dataclass(frozen=True)
class Geometry:
    x: int
    y: int
    width: int
    height: int


@dataclass(frozen=True)
class MonitorInfo:
    name: str
    x: int
    y: int
    width: int
    height: int


def resolve_startup_geometry(
    saved_state: WindowState | None,
    available_monitors: list[MonitorInfo],
    default_size: tuple[int, int],
) -> tuple[Geometry, str | None]:
    """Return (geometry, monitor_name_to_remember).

    If a saved window state exists and its monitor is still connected,
    restore the exact saved geometry on it. Otherwise (no saved state, or
    that monitor is gone), center a window of `default_size` on the first
    available monitor.
    """
    default_w, default_h = default_size
    if saved_state is not None:
        monitor = next((m for m in available_monitors if m.name == saved_state.monitor_name), None)
        if monitor is not None:
            return (
                Geometry(saved_state.x, saved_state.y, saved_state.width, saved_state.height),
                monitor.name,
            )
    if not available_monitors:
        return Geometry(0, 0, default_w, default_h), None
    primary = available_monitors[0]
    x = primary.x + (primary.width - default_w) // 2
    y = primary.y + (primary.height - default_h) // 2
    return Geometry(x, y, default_w, default_h), primary.name
