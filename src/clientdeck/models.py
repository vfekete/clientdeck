"""Qt model wrappers exposing `ConfigStore` data to QML."""

from __future__ import annotations

from PySide6.QtCore import Property, QAbstractListModel, QModelIndex, Qt, Signal, Slot

from .config import AppEntry, ClientEntry, ConfigStore


class ClientListModel(QAbstractListModel):
    NameRole = Qt.UserRole + 1
    DescriptionRole = Qt.UserRole + 2
    UsernameRole = Qt.UserRole + 3
    LogoPathRole = Qt.UserRole + 4
    AppsRole = Qt.UserRole + 5

    _ROLE_NAMES = {
        NameRole: b"name",
        DescriptionRole: b"description",
        UsernameRole: b"username",
        LogoPathRole: b"logoPath",
        AppsRole: b"apps",
    }

    countChanged = Signal()
    clientAdded = Signal(str)

    def __init__(self, store: ConfigStore, parent=None):
        super().__init__(parent)
        self._store = store

    # -- QAbstractListModel interface ------------------------------------

    def rowCount(self, parent: QModelIndex = QModelIndex()) -> int:
        if parent.isValid():
            return 0
        return len(self._store.clients)

    def roleNames(self) -> dict:
        return dict(self._ROLE_NAMES)

    def data(self, index: QModelIndex, role: int = Qt.DisplayRole):
        if not index.isValid() or not (0 <= index.row() < len(self._store.clients)):
            return None
        client = self._store.clients[index.row()]
        if role == self.NameRole:
            return client.name
        if role == self.DescriptionRole:
            return client.description
        if role == self.UsernameRole:
            return client.username
        if role == self.LogoPathRole:
            return client.logo_path
        if role == self.AppsRole:
            return [
                {"name": a.name, "command": a.command, "icon": a.icon, "useSu": a.use_su}
                for a in client.apps
            ]
        return None

    @Property(int, notify=countChanged)
    def count(self) -> int:
        return len(self._store.clients)

    # -- QML-callable mutators -------------------------------------------

    @Slot(str, str, str, str)
    def addClient(self, name: str, description: str, username: str, logo_path: str = "") -> None:
        row = len(self._store.clients)
        self.beginInsertRows(QModelIndex(), row, row)
        self._store.add_client(
            ClientEntry(name=name, description=description, username=username, logo_path=logo_path or None)
        )
        self.endInsertRows()
        self.countChanged.emit()
        self.clientAdded.emit(username)

    @Slot(str, str, str, str, str)
    def updateClient(
        self, old_username: str, name: str, description: str, new_username: str, logo_path: str = ""
    ) -> None:
        row = next((i for i, c in enumerate(self._store.clients) if c.username == old_username), None)
        if row is None:
            return
        self._store.update_client(old_username, name, description, new_username, logo_path or None)
        index = self.index(row, 0)
        self.dataChanged.emit(index, index, [self.NameRole, self.DescriptionRole, self.UsernameRole, self.LogoPathRole])

    @Slot(str)
    def removeClient(self, username: str) -> None:
        row = next((i for i, c in enumerate(self._store.clients) if c.username == username), None)
        if row is None:
            return
        self.beginRemoveRows(QModelIndex(), row, row)
        self._store.remove_client(username)
        self.endRemoveRows()
        self.countChanged.emit()

    @Slot(str, str, str, bool, str, str)
    def addAppToClient(
        self, username: str, app_name: str, command: str, use_su: bool, working_dir: str = "", icon: str = ""
    ) -> None:
        row = next((i for i, c in enumerate(self._store.clients) if c.username == username), None)
        if row is None:
            return
        self._store.add_app(
            username,
            AppEntry(name=app_name, command=command, working_dir=working_dir or None, use_su=use_su, icon=icon or None),
        )
        index = self.index(row, 0)
        self.dataChanged.emit(index, index, [self.AppsRole])

    @Slot(str, int)
    def removeAppFromClient(self, username: str, app_index: int) -> None:
        row = next((i for i, c in enumerate(self._store.clients) if c.username == username), None)
        if row is None:
            return
        self._store.remove_app(username, app_index)
        index = self.index(row, 0)
        self.dataChanged.emit(index, index, [self.AppsRole])

    @Slot(str, int, int)
    def moveApp(self, username: str, from_index: int, to_index: int) -> None:
        row = next((i for i, c in enumerate(self._store.clients) if c.username == username), None)
        if row is None:
            return
        self._store.move_app(username, from_index, to_index)
        index = self.index(row, 0)
        self.dataChanged.emit(index, index, [self.AppsRole])
