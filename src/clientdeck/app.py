"""Application entry point: wires config, models, and QML together.

Not covered by the pytest suite; smoke-tested headlessly instead. See
docs/comments-details.md [2].
"""

from __future__ import annotations

import shlex
import signal
import socket
import subprocess
import sys

from PySide6.QtCore import Property, QObject, QTimer, QUrl, Signal, Slot
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine

from . import __version__
from .compositor import enable_blur_behind_if_supported
from .config import AppEntry, ConfigStore, WindowState
from .desktop_apps import discover_desktop_apps
from .icon_provider import ThemeIconProvider, ensure_icon_theme_configured
from .loader_ipc import maybe_launch_loader
from .models import ClientListModel
from .ps1 import (
    DARK_TERMINAL,
    DEFAULT_PS1,
    HINTS,
    LIGHT_TERMINAL,
    PRESETS,
    PromptContext,
    render_session_html,
    render_title,
)
from .paths import get_qml_dir, get_resources_dir, get_scripts_dir, is_packaged_build
from .username import username_or_group_exists
from .window_placement import MonitorInfo, resolve_startup_geometry

DEFAULT_WINDOW_SIZE = (900, 500)


class _ClientProvisioner(QObject):
    """Creates the client's Linux user account via the polkit-gated script.

    Runs synchronously (blocks on the pkexec auth dialog). See
    docs/comments-details.md [3].
    """

    @Slot(str, result=bool)
    def createLinuxUser(self, username: str) -> bool:
        # Invoked by its own shebang, not sys.executable — see [4].
        result = subprocess.run(["pkexec", str(get_scripts_dir() / "create_user.py"), username])
        return result.returncode == 0

    @Slot(str, result=bool)
    def deleteLinuxUser(self, username: str) -> bool:
        # Removes the old account when a client is renamed and the user
        # opts to delete rather than orphan it. See [3] for the MOCK_MODE
        # caveat.
        result = subprocess.run(["pkexec", str(get_scripts_dir() / "delete_user.py"), username])
        return result.returncode == 0


class _UsernameChecker(QObject):
    @Slot(str, result=bool)
    def isTaken(self, name: str) -> bool:
        return username_or_group_exists(name)


class _FocusTracker(QObject):
    """Exposes the application's focus window to QML — see [137]."""

    focusWindowChanged = Signal()

    def __init__(self, app: QGuiApplication, parent: QObject | None = None):
        super().__init__(parent)
        self._app = app
        app.focusWindowChanged.connect(lambda _window: self.focusWindowChanged.emit())

    @Property(QObject, notify=focusWindowChanged)
    def focusWindow(self) -> QObject | None:
        return self._app.focusWindow()


class _Ps1Renderer(QObject):
    """PS1 preview HTML, presets and colon hints for QML — see [130]."""

    def __init__(self, parent: QObject | None = None):
        super().__init__(parent)
        full = socket.gethostname() or "hostname"
        self._hostname, self._full_hostname = full.split(".", 1)[0], full

    def _context(self, username: str) -> PromptContext:
        return PromptContext(
            username=username or "user", hostname=self._hostname, full_hostname=self._full_hostname
        )

    @Slot(str, str, bool, result=str)
    def renderSession(self, ps1: str, username: str, dark: bool) -> str:
        return render_session_html(ps1, self._context(username), dark)

    @Slot(str, str, result=str)
    def title(self, ps1: str, username: str) -> str:
        return render_title(ps1, self._context(username))

    @Slot(bool, result="QVariantMap")
    def terminalColors(self, dark: bool) -> dict:
        c = DARK_TERMINAL if dark else LIGHT_TERMINAL
        return {
            "background": c.background,
            "foreground": c.foreground,
            "titleBar": c.title_bar,
            "titleText": c.title_text,
            "border": c.border,
        }

    @Slot(result=str)
    def defaultPs1(self) -> str:
        return DEFAULT_PS1

    @Slot(result=list)
    def presets(self) -> list:
        return [{"name": name, "ps1": ps1} for name, ps1 in PRESETS]

    @Slot(result=list)
    def hints(self) -> list:
        return [{"keyword": k, "value": v, "description": d} for k, v, d in HINTS]


class _DesktopAppsProvider(QObject):
    @Slot(result=list)
    def discover(self) -> list:
        return [
            {"name": a.name, "command": a.exec_command, "icon": a.icon, "workingDir": a.working_dir or ""}
            for a in discover_desktop_apps()
        ]


class _AppLauncher(QObject):
    """Spawns `launch_as_user.py` for one of a client's app buttons.

    See docs/comments-details.md [5].
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
    # Invoked by its own shebang — see [4].
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
    # As close to the first action as possible — see [113].
    loader = maybe_launch_loader()

    app = QGuiApplication(argv if argv is not None else sys.argv)
    app.setApplicationName("ClientDeck")
    app.setApplicationVersion(__version__)
    ensure_icon_theme_configured()

    # Makes Ctrl+C actually quit (source builds only) — see [6].
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
    ps1_renderer = _Ps1Renderer()
    focus_tracker = _FocusTracker(app)

    geometry, _initial_monitor_name = resolve_startup_geometry(
        store.window_state, _monitor_infos(app), default_size=DEFAULT_WINDOW_SIZE
    )

    engine = QQmlApplicationEngine()
    # Resolves image://theme/<name> via the desktop icon theme — see [7].
    theme_icon_provider = ThemeIconProvider()
    engine.addImageProvider("theme", theme_icon_provider)
    # Explicit long-lived refs, needed to avoid a GC gotcha — see [8].
    engine._retained_context_objects = [
        client_model,
        client_provisioner,
        username_checker,
        desktop_apps_provider,
        app_launcher,
        ps1_renderer,
        focus_tracker,
    ]
    context = engine.rootContext()
    context.setContextProperty("clientModel", client_model)
    context.setContextProperty("clientProvisioner", client_provisioner)
    context.setContextProperty("usernameChecker", username_checker)
    context.setContextProperty("desktopAppsProvider", desktop_apps_provider)
    context.setContextProperty("appLauncher", app_launcher)
    context.setContextProperty("ps1Renderer", ps1_renderer)
    context.setContextProperty("focusTracker", focus_tracker)
    context.setContextProperty("initialX", geometry.x)
    context.setContextProperty("initialY", geometry.y)
    context.setContextProperty("initialWidth", geometry.width)
    context.setContextProperty("initialHeight", geometry.height)
    # Fed to Theme.qml's noItemSource — see docs/comments-details.md [125].
    context.setContextProperty("noItemDarkThemePath", str(get_resources_dir() / "no-item-dark.png"))
    context.setContextProperty("noItemLightThemePath", str(get_resources_dir() / "no-item-light.png"))

    # No addImportPath() needed — see [9].
    qml_dir = get_qml_dir()
    engine.load(QUrl.fromLocalFile(str(qml_dir / "Main.qml")))
    if not engine.rootObjects():
        loader.close()
        return 1

    window = engine.rootObjects()[0]

    # Best-effort real backdrop blur, X11-only — see [10].
    if app.platformName() == "xcb":
        enable_blur_behind_if_supported(int(window.winId()))

    # Pumps the event loop so the window has actually painted, not just
    # been shown, before telling the loader to fade out — see [114].
    app.processEvents()
    app.processEvents()
    loader.send_running()
    loader.close()

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
