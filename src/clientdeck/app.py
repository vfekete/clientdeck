"""Application entry point: wires config, models, and QML together.

NOTE: this module isn't covered by the pytest suite — it needs a real Qt
GUI platform, which the agent's sandbox can't provide for an actual window
(see CLAUDE.md's "Environment constraints"). It *has* been smoke-tested
headlessly with `QT_QPA_PLATFORM=offscreen` (Qt's no-display platform
plugin — doesn't pop a window, so it doesn't violate that constraint),
which is how the QML module-import bug and the packaged-build asset-path
bugs documented in build.sh/paths.py were actually caught and fixed, rather
than just written to spec and hoped for. Still needs manual, on-host
verification for anything that plugin can't exercise: real visual
rendering/theme appearance, window-manager interaction (drag, monitor
placement/restore across a real multi-monitor setup), and the
`su`/`xhost`/`pkexec` launch flows.
"""

from __future__ import annotations

import shlex
import signal
import subprocess
import sys

from PySide6.QtCore import QObject, QTimer, QUrl, Slot
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine

from . import __version__
from .compositor import enable_blur_behind_if_supported
from .config import AppEntry, ConfigStore, WindowState
from .desktop_apps import discover_desktop_apps
from .icon_provider import ThemeIconProvider, ensure_icon_theme_configured
from .models import ClientListModel
from .paths import get_qml_dir, get_scripts_dir, is_packaged_build
from .username import username_or_group_exists
from .window_placement import MonitorInfo, resolve_startup_geometry

DEFAULT_WINDOW_SIZE = (900, 500)


class _ClientProvisioner(QObject):
    """Creates the client's Linux user account via the polkit-gated script.

    Runs synchronously (blocks on the pkexec auth dialog) — acceptable for
    an infrequent "add client" action; not attempted asynchronously here to
    avoid the added complexity of a QML-visible pending state for something
    this rare.

    NOTE: while the app is in UI/UX-prototyping phase, `create_user.py`'s
    own MOCK_MODE means this still runs the real pkexec authentication
    flow but does not actually create a Linux user — see that script's
    module docstring.
    """

    @Slot(str, result=bool)
    def createLinuxUser(self, username: str) -> bool:
        # Invoked by its own shebang (`#!/usr/bin/env python3`), not
        # `sys.executable` — in a packaged build `sys.executable` is the
        # compiled ClientDeck binary itself, not a Python interpreter.
        result = subprocess.run(["pkexec", str(get_scripts_dir() / "create_user.py"), username])
        return result.returncode == 0

    @Slot(str, result=bool)
    def deleteLinuxUser(self, username: str) -> bool:
        # Used when a client is renamed and the user opts, in the "delete
        # original content?" prompt, to remove the old account rather than
        # leave it orphaned on disk. Same MOCK_MODE caveat as create_user.py.
        result = subprocess.run(["pkexec", str(get_scripts_dir() / "delete_user.py"), username])
        return result.returncode == 0


class _UsernameChecker(QObject):
    @Slot(str, result=bool)
    def isTaken(self, name: str) -> bool:
        return username_or_group_exists(name)


class _DesktopAppsProvider(QObject):
    @Slot(result=list)
    def discover(self) -> list:
        return [
            {"name": a.name, "command": a.exec_command, "icon": a.icon, "workingDir": a.working_dir or ""}
            for a in discover_desktop_apps()
        ]


class _AppLauncher(QObject):
    """Spawns `launch_as_user.py` for one of a client's app buttons.

    Every app a client has is added via the "add app" dialog — there are
    no hardcoded/builtin apps (a terminal, an editor, etc. are just apps
    like any other, added the same way).

    NOTE: while the app is in UI/UX-prototyping phase, `launch_as_user.py`'s
    own MOCK_MODE means no `su`/`xhost`/actual app process happens — see
    that script's module docstring.
    """

    def __init__(self, store: ConfigStore, parent: QObject | None = None):
        super().__init__(parent)
        self._store = store

    @Slot(str, int)
    def launchApp(self, username: str, app_index: int) -> None:
        client = self._store.get_client(username)
        if client is None or not (0 <= app_index < len(client.apps)):
            return
        app: AppEntry = client.apps[app_index]
        command = shlex.split(app.command)
        if not command:
            return
        _spawn_launch_script(username, command, workdir=app.working_dir, gui=True)


def _spawn_launch_script(username: str, command: list[str], workdir: str | None, gui: bool) -> None:
    # Invoked by its own shebang, same reasoning as createLinuxUser above.
    argv = [str(get_scripts_dir() / "launch_as_user.py"), "--username", username]
    if workdir:
        argv += ["--workdir", workdir]
    if gui:
        argv.append("--gui")
    argv += command
    subprocess.Popen(argv)


def _monitor_infos(app: QGuiApplication) -> list[MonitorInfo]:
    infos = []
    for screen in app.screens():
        geo = screen.geometry()
        infos.append(MonitorInfo(name=screen.name(), x=geo.x(), y=geo.y(), width=geo.width(), height=geo.height()))
    return infos


def run(argv: list[str] | None = None) -> int:
    app = QGuiApplication(argv if argv is not None else sys.argv)
    app.setApplicationName("ClientDeck")
    app.setApplicationVersion(__version__)
    ensure_icon_theme_configured()

    # Qt's C++ event loop never yields back to the Python interpreter on
    # its own, so a bare `signal.signal(SIGINT, ...)` handler installed here
    # would never actually run — Ctrl+C in a terminal would do nothing
    # until/unless something else caused Python to regain control. A
    # trivial repeating QTimer forces that handoff regularly, so the
    # handler (which triggers the normal app.quit() shutdown path, saving
    # window state via aboutToQuit like any other quit) actually fires.
    #
    # Source mode only (run.sh / `uv run python -m clientdeck`): confirmed
    # working there, but the packaged onefile binary is actually two
    # processes (a bootstrap plus the extracted payload it execs) and
    # SIGINT delivered to that process group does not reach this handler
    # the same way — see CHANGELOG.md. Rather than install something known
    # not to behave correctly there, skip it entirely for a packaged build.
    if not is_packaged_build():
        signal.signal(signal.SIGINT, lambda *_args: app.quit())
        sigint_pump = QTimer()
        sigint_pump.timeout.connect(lambda: None)
        sigint_pump.start(200)

    store = ConfigStore()
    client_model = ClientListModel(store)
    client_provisioner = _ClientProvisioner()
    username_checker = _UsernameChecker()
    desktop_apps_provider = _DesktopAppsProvider()
    app_launcher = _AppLauncher(store)

    geometry, _initial_monitor_name = resolve_startup_geometry(
        store.window_state, _monitor_infos(app), default_size=DEFAULT_WINDOW_SIZE
    )

    engine = QQmlApplicationEngine()
    # Makes `image://theme/<name>` resolve via the desktop's actual icon
    # theme (see icon_provider.py) — AddAppDialog.qml uses this for
    # discovered .desktop apps whose Icon= is a theme name rather than an
    # absolute path, which is the common case. addImageProvider() transfers
    # ownership to the engine (per Qt docs), but named here rather than
    # passed as a bare temporary anyway, matching this function's existing
    # explicit-reference-pinning practice below for context-property
    # objects (a different, real gotcha, but the same defensive habit).
    theme_icon_provider = ThemeIconProvider()
    engine.addImageProvider("theme", theme_icon_provider)
    # Pin these on `engine` explicitly (not just relying on them being
    # local variables in this function's frame): a QObject handed to
    # setContextProperty() is only *referenced* by the QML side, not
    # Python-refcounted through it, so without an explicit long-lived
    # Python reference it can be garbage-collected out from under a live
    # QML binding — intermittently, since it depends on GC timing. This
    # is a well-known PySide6/PyQt gotcha; observed here as an occasional
    # (roughly 1-in-5 runs) "TypeError: Cannot read property 'count' of
    # null" for `clientModel` in Main.qml, on an otherwise-unchanged QML
    # file with no edits between a clean run and a failing one.
    engine._retained_context_objects = [
        client_model,
        client_provisioner,
        username_checker,
        desktop_apps_provider,
        app_launcher,
    ]
    context = engine.rootContext()
    context.setContextProperty("clientModel", client_model)
    context.setContextProperty("clientProvisioner", client_provisioner)
    context.setContextProperty("usernameChecker", username_checker)
    context.setContextProperty("desktopAppsProvider", desktop_apps_provider)
    context.setContextProperty("appLauncher", app_launcher)
    context.setContextProperty("initialX", geometry.x)
    context.setContextProperty("initialY", geometry.y)
    context.setContextProperty("initialWidth", geometry.width)
    context.setContextProperty("initialHeight", geometry.height)

    # No addImportPath() needed: Main.qml and the qmldir declaring the
    # "ClientDeck" module live in the same directory, so Qt's automatic
    # local-directory import already gives every file there access to it
    # (confirmed the hard way — an explicit `import ClientDeck 1.0` in the
    # QML files resolved to "module ClientDeck is not installed", since
    # that path-based module lookup expects a directory literally named
    # ClientDeck/, not one that merely declares that module name).
    qml_dir = get_qml_dir()
    engine.load(QUrl.fromLocalFile(str(qml_dir / "Main.qml")))
    if not engine.rootObjects():
        return 1

    window = engine.rootObjects()[0]

    # Real backdrop blur (vs. the plain alpha-transparency Main.qml/Theme.qml
    # already do) is compositor-specific and X11-only here — see
    # compositor.py. Best-effort and silently a no-op anywhere it doesn't
    # apply (Wayland, GNOME/Mutter, a WM that isn't KWin, no Xlib, ...).
    if app.platformName() == "xcb":
        enable_blur_behind_if_supported(int(window.winId()))

    def _persist_window_state() -> None:
        screen = window.screen()
        store.set_window_state(
            WindowState(
                x=window.x(),
                y=window.y(),
                width=window.width(),
                height=window.height(),
                monitor_name=screen.name() if screen is not None else None,
            )
        )

    app.aboutToQuit.connect(_persist_window_state)

    return app.exec()


def main() -> int:
    return run()
