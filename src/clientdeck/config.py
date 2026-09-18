"""Persisted app configuration: clients, their apps, and window state.

Stored as a single JSON file under the user's XDG config directory, written
atomically (temp file + rename) so a crash mid-write never corrupts the
previous good config. There is no explicit "save" step for the user — every
mutating method persists immediately.
"""

from __future__ import annotations

import json
import os
import tempfile
from dataclasses import asdict, dataclass, field
from pathlib import Path

CONFIG_DIR_ENV = "CLIENTDECK_CONFIG_DIR"
CONFIG_FILENAME = "config.json"
CONFIG_VERSION = 1


def get_config_dir() -> Path:
    override = os.environ.get(CONFIG_DIR_ENV)
    if override:
        return Path(override)
    xdg_config_home = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
    return Path(xdg_config_home) / "clientdeck"


def get_config_path() -> Path:
    return get_config_dir() / CONFIG_FILENAME


@dataclass
class AppEntry:
    name: str
    command: str
    working_dir: str | None = None
    use_su: bool = True
    icon: str | None = None

    def to_dict(self) -> dict:
        return asdict(self)

    @classmethod
    def from_dict(cls, data: dict) -> "AppEntry":
        return cls(
            name=data["name"],
            command=data["command"],
            working_dir=data.get("working_dir"),
            use_su=data.get("use_su", True),
            icon=data.get("icon"),
        )


@dataclass
class ClientEntry:
    name: str
    description: str
    username: str
    logo_path: str | None = None
    apps: list[AppEntry] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "name": self.name,
            "description": self.description,
            "username": self.username,
            "logo_path": self.logo_path,
            "apps": [app.to_dict() for app in self.apps],
        }

    @classmethod
    def from_dict(cls, data: dict) -> "ClientEntry":
        return cls(
            name=data["name"],
            description=data.get("description", ""),
            username=data["username"],
            logo_path=data.get("logo_path"),
            apps=[AppEntry.from_dict(a) for a in data.get("apps", [])],
        )


@dataclass
class WindowState:
    x: int
    y: int
    width: int
    height: int
    monitor_name: str | None = None

    def to_dict(self) -> dict:
        return asdict(self)

    @classmethod
    def from_dict(cls, data: dict) -> "WindowState":
        return cls(
            x=data["x"],
            y=data["y"],
            width=data["width"],
            height=data["height"],
            monitor_name=data.get("monitor_name"),
        )


class ConfigStore:
    """Loads/persists ClientDeck's config.json."""

    def __init__(self, path: Path | None = None):
        self.path = path or get_config_path()
        self.clients: list[ClientEntry] = []
        self.window_state: WindowState | None = None
        self.load()

    def load(self) -> None:
        if not self.path.exists():
            self.clients = []
            self.window_state = None
            return
        try:
            data = json.loads(self.path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            # Corrupt/unreadable config: start fresh rather than crash the app.
            self.clients = []
            self.window_state = None
            return
        self.clients = [ClientEntry.from_dict(c) for c in data.get("clients", [])]
        window = data.get("window_state")
        self.window_state = WindowState.from_dict(window) if window else None

    def save(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        data = {
            "version": CONFIG_VERSION,
            "clients": [c.to_dict() for c in self.clients],
            "window_state": self.window_state.to_dict() if self.window_state else None,
        }
        fd, tmp_name = tempfile.mkstemp(dir=self.path.parent, prefix=".config-", suffix=".tmp")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as fh:
                json.dump(data, fh, indent=2)
            os.replace(tmp_name, self.path)
        except BaseException:
            Path(tmp_name).unlink(missing_ok=True)
            raise

    def get_client(self, username: str) -> ClientEntry | None:
        return next((c for c in self.clients if c.username == username), None)

    def add_client(self, client: ClientEntry) -> None:
        self.clients.append(client)
        self.save()

    def remove_client(self, username: str) -> None:
        self.clients = [c for c in self.clients if c.username != username]
        self.save()

    def update_client(
        self, old_username: str, name: str, description: str, new_username: str, logo_path: str | None
    ) -> None:
        """Edits an existing client's fields in place — including,
        possibly, its username, which is otherwise this store's lookup key
        everywhere else. Mutating the same ClientEntry (rather than
        remove+re-add) keeps its `apps` list attached across a rename."""
        client = self.get_client(old_username)
        if client is None:
            raise KeyError(f"no client with username {old_username!r}")
        client.name = name
        client.description = description
        client.username = new_username
        client.logo_path = logo_path
        self.save()

    def add_app(self, username: str, app: AppEntry) -> None:
        client = self.get_client(username)
        if client is None:
            raise KeyError(f"no client with username {username!r}")
        client.apps.append(app)
        self.save()

    def remove_app(self, username: str, index: int) -> None:
        client = self.get_client(username)
        if client is None or not (0 <= index < len(client.apps)):
            return
        del client.apps[index]
        self.save()

    def move_app(self, username: str, from_index: int, to_index: int) -> None:
        """Reorders one client's apps — used by drag-and-drop reordering in
        ClientRow.qml. Both endpoints (including moving to the very first
        or very last position) are valid; out-of-range indices are a no-op
        rather than an error, since this is driven by live UI state that
        could in principle race with a concurrent removal."""
        client = self.get_client(username)
        if client is None or not (0 <= from_index < len(client.apps)) or not (0 <= to_index < len(client.apps)):
            return
        if from_index == to_index:
            return
        app = client.apps.pop(from_index)
        client.apps.insert(to_index, app)
        self.save()

    def set_window_state(self, state: WindowState) -> None:
        self.window_state = state
        self.save()
