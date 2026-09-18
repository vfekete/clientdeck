from __future__ import annotations

from clientdeck.config import WindowState
from clientdeck.window_placement import Geometry, MonitorInfo, resolve_startup_geometry


def test_no_saved_state_centers_on_first_monitor():
    monitors = [MonitorInfo(name="DP-1", x=0, y=0, width=1920, height=1080)]

    geometry, monitor_name = resolve_startup_geometry(None, monitors, default_size=(900, 500))

    assert geometry == Geometry(x=(1920 - 900) // 2, y=(1080 - 500) // 2, width=900, height=500)
    assert monitor_name == "DP-1"


def test_saved_monitor_still_connected_restores_exact_geometry():
    saved = WindowState(x=123, y=45, width=1000, height=700, monitor_name="DP-2")
    monitors = [
        MonitorInfo(name="DP-1", x=0, y=0, width=1920, height=1080),
        MonitorInfo(name="DP-2", x=1920, y=0, width=2560, height=1440),
    ]

    geometry, monitor_name = resolve_startup_geometry(saved, monitors, default_size=(900, 500))

    assert geometry == Geometry(x=123, y=45, width=1000, height=700)
    assert monitor_name == "DP-2"


def test_saved_monitor_disconnected_falls_back_to_centering_on_first():
    saved = WindowState(x=123, y=45, width=1000, height=700, monitor_name="DP-2-unplugged")
    monitors = [MonitorInfo(name="DP-1", x=0, y=0, width=1920, height=1080)]

    geometry, monitor_name = resolve_startup_geometry(saved, monitors, default_size=(900, 500))

    assert geometry == Geometry(x=(1920 - 900) // 2, y=(1080 - 500) // 2, width=900, height=500)
    assert monitor_name == "DP-1"


def test_no_monitors_available_returns_origin_default_size():
    geometry, monitor_name = resolve_startup_geometry(None, [], default_size=(900, 500))

    assert geometry == Geometry(x=0, y=0, width=900, height=500)
    assert monitor_name is None


def test_first_available_monitor_neednt_be_at_origin():
    monitors = [MonitorInfo(name="DP-1", x=1920, y=0, width=1280, height=1024)]

    geometry, monitor_name = resolve_startup_geometry(None, monitors, default_size=(900, 500))

    assert geometry == Geometry(x=1920 + (1280 - 900) // 2, y=(1024 - 500) // 2, width=900, height=500)
    assert monitor_name == "DP-1"
