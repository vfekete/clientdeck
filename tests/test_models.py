from __future__ import annotations

from PySide6.QtCore import QModelIndex

from clientdeck.config import ClientEntry, ConfigStore
from clientdeck.models import ClientListModel


def _model(tmp_path) -> ClientListModel:
    store = ConfigStore(path=tmp_path / "config.json")
    return ClientListModel(store)


def test_empty_model_has_zero_count(tmp_path):
    model = _model(tmp_path)
    assert model.count == 0
    assert model.rowCount() == 0


def test_add_client_updates_count_and_roles(tmp_path):
    model = _model(tmp_path)

    model.addClient("Acme", "Acme Corp", "acme", "")

    assert model.count == 1
    index = model.index(0, 0)
    assert model.data(index, ClientListModel.NameRole) == "Acme"
    assert model.data(index, ClientListModel.DescriptionRole) == "Acme Corp"
    assert model.data(index, ClientListModel.UsernameRole) == "acme"
    assert model.data(index, ClientListModel.AppsRole) == []


def test_add_app_to_client_shows_up_in_apps_role(tmp_path):
    model = _model(tmp_path)
    model.addClient("Acme", "", "acme", "")

    model.addAppToClient("acme", "Terminal", "x-terminal-emulator", True, "")

    index = model.index(0, 0)
    apps = model.data(index, ClientListModel.AppsRole)
    assert apps == [{"name": "Terminal", "command": "x-terminal-emulator", "icon": None, "useSu": True}]


def test_add_app_to_client_with_icon_shows_up_in_apps_role(tmp_path):
    model = _model(tmp_path)
    model.addClient("Acme", "", "acme", "")

    model.addAppToClient("acme", "Firefox", "firefox", True, "", "firefox")

    index = model.index(0, 0)
    apps = model.data(index, ClientListModel.AppsRole)
    assert apps == [{"name": "Firefox", "command": "firefox", "icon": "firefox", "useSu": True}]


def test_add_app_to_unknown_client_is_a_noop(tmp_path):
    model = _model(tmp_path)
    model.addAppToClient("nobody", "Terminal", "x-terminal-emulator", True, "")
    assert model.count == 0


def test_remove_app_from_client_updates_apps_role(tmp_path):
    model = _model(tmp_path)
    model.addClient("Acme", "", "acme", "")
    model.addAppToClient("acme", "Terminal", "term", True)
    model.addAppToClient("acme", "Editor", "editor", True)

    model.removeAppFromClient("acme", 0)

    apps = model.data(model.index(0, 0), ClientListModel.AppsRole)
    assert [a["name"] for a in apps] == ["Editor"]


def test_remove_app_from_unknown_client_is_a_noop(tmp_path):
    model = _model(tmp_path)
    model.removeAppFromClient("nobody", 0)
    assert model.count == 0


def test_move_app_reorders_apps_role(tmp_path):
    model = _model(tmp_path)
    model.addClient("Acme", "", "acme", "")
    model.addAppToClient("acme", "A", "a", True)
    model.addAppToClient("acme", "B", "b", True)
    model.addAppToClient("acme", "C", "c", True)

    model.moveApp("acme", 0, 2)

    apps = model.data(model.index(0, 0), ClientListModel.AppsRole)
    assert [a["name"] for a in apps] == ["B", "C", "A"]


def test_move_app_on_unknown_client_is_a_noop(tmp_path):
    model = _model(tmp_path)
    model.moveApp("nobody", 0, 1)
    assert model.count == 0


def test_update_client_edits_fields_shown_in_apps_role_client(tmp_path):
    model = _model(tmp_path)
    model.addClient("Acme", "old desc", "acme", "")

    model.updateClient("acme", "Acme Corp", "new desc", "acme", "/logo.png")

    index = model.index(0, 0)
    assert model.data(index, ClientListModel.NameRole) == "Acme Corp"
    assert model.data(index, ClientListModel.DescriptionRole) == "new desc"
    assert model.data(index, ClientListModel.UsernameRole) == "acme"
    assert model.data(index, ClientListModel.LogoPathRole) == "/logo.png"


def test_update_client_rename_keeps_apps(tmp_path):
    model = _model(tmp_path)
    model.addClient("Acme", "", "acme", "")
    model.addAppToClient("acme", "Terminal", "term", True)

    model.updateClient("acme", "Acme", "", "acme2", "")

    index = model.index(0, 0)
    assert model.data(index, ClientListModel.UsernameRole) == "acme2"
    apps = model.data(index, ClientListModel.AppsRole)
    assert [a["name"] for a in apps] == ["Terminal"]


def test_update_client_unknown_username_is_a_noop(tmp_path):
    model = _model(tmp_path)
    model.updateClient("nobody", "X", "", "nobody2", "")
    assert model.count == 0


def test_remove_client_updates_count(tmp_path):
    model = _model(tmp_path)
    model.addClient("Acme", "", "acme", "")
    model.addClient("Beta", "", "beta", "")

    model.removeClient("acme")

    assert model.count == 1
    assert model.data(model.index(0, 0), ClientListModel.UsernameRole) == "beta"


def test_data_out_of_range_returns_none(tmp_path):
    model = _model(tmp_path)
    assert model.data(model.index(0, 0), ClientListModel.NameRole) is None
    assert model.data(QModelIndex(), ClientListModel.NameRole) is None


def test_role_names_exposed_for_qml(tmp_path):
    model = _model(tmp_path)
    names = model.roleNames()
    assert names[ClientListModel.NameRole] == b"name"
    assert names[ClientListModel.UsernameRole] == b"username"
    assert names[ClientListModel.AppsRole] == b"apps"
