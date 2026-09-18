from __future__ import annotations

from clientdeck.config import AppEntry, ClientEntry, ConfigStore, WindowState


def test_fresh_store_is_empty(tmp_path):
    store = ConfigStore(path=tmp_path / "config.json")
    assert store.clients == []
    assert store.window_state is None


def test_add_client_persists_and_reloads(tmp_path):
    path = tmp_path / "config.json"
    store = ConfigStore(path=path)
    store.add_client(ClientEntry(name="Acme", description="Acme Corp", username="acme"))

    assert path.exists()
    reloaded = ConfigStore(path=path)
    assert len(reloaded.clients) == 1
    assert reloaded.clients[0].name == "Acme"
    assert reloaded.clients[0].username == "acme"


def test_add_app_to_client(tmp_path):
    store = ConfigStore(path=tmp_path / "config.json")
    store.add_client(ClientEntry(name="Acme", description="", username="acme"))
    store.add_app("acme", AppEntry(name="Terminal", command="x-terminal-emulator"))

    reloaded = ConfigStore(path=store.path)
    assert len(reloaded.clients[0].apps) == 1
    assert reloaded.clients[0].apps[0].name == "Terminal"
    assert reloaded.clients[0].apps[0].use_su is True


def test_add_app_to_unknown_client_raises(tmp_path):
    store = ConfigStore(path=tmp_path / "config.json")
    try:
        store.add_app("nobody", AppEntry(name="x", command="x"))
    except KeyError:
        pass
    else:
        raise AssertionError("expected KeyError for unknown client")


def test_remove_app(tmp_path):
    store = ConfigStore(path=tmp_path / "config.json")
    store.add_client(ClientEntry(name="Acme", description="", username="acme"))
    store.add_app("acme", AppEntry(name="Terminal", command="term"))
    store.add_app("acme", AppEntry(name="Editor", command="editor"))

    store.remove_app("acme", 0)

    reloaded = ConfigStore(path=store.path)
    assert [a.name for a in reloaded.clients[0].apps] == ["Editor"]


def test_remove_app_out_of_range_is_a_noop(tmp_path):
    store = ConfigStore(path=tmp_path / "config.json")
    store.add_client(ClientEntry(name="Acme", description="", username="acme"))
    store.add_app("acme", AppEntry(name="Terminal", command="term"))

    store.remove_app("acme", 5)
    store.remove_app("nobody", 0)

    assert len(store.clients[0].apps) == 1


def test_move_app_reorders_and_persists(tmp_path):
    store = ConfigStore(path=tmp_path / "config.json")
    store.add_client(ClientEntry(name="Acme", description="", username="acme"))
    store.add_app("acme", AppEntry(name="A", command="a"))
    store.add_app("acme", AppEntry(name="B", command="b"))
    store.add_app("acme", AppEntry(name="C", command="c"))

    store.move_app("acme", 0, 2)  # move "A" to the very last position

    reloaded = ConfigStore(path=store.path)
    assert [a.name for a in reloaded.clients[0].apps] == ["B", "C", "A"]


def test_move_app_to_first_position(tmp_path):
    store = ConfigStore(path=tmp_path / "config.json")
    store.add_client(ClientEntry(name="Acme", description="", username="acme"))
    store.add_app("acme", AppEntry(name="A", command="a"))
    store.add_app("acme", AppEntry(name="B", command="b"))
    store.add_app("acme", AppEntry(name="C", command="c"))

    store.move_app("acme", 2, 0)  # move "C" to the very first position

    assert [a.name for a in store.clients[0].apps] == ["C", "A", "B"]


def test_move_app_same_index_is_a_noop(tmp_path):
    store = ConfigStore(path=tmp_path / "config.json")
    store.add_client(ClientEntry(name="Acme", description="", username="acme"))
    store.add_app("acme", AppEntry(name="A", command="a"))

    store.move_app("acme", 0, 0)

    assert [a.name for a in store.clients[0].apps] == ["A"]


def test_move_app_out_of_range_is_a_noop(tmp_path):
    store = ConfigStore(path=tmp_path / "config.json")
    store.add_client(ClientEntry(name="Acme", description="", username="acme"))
    store.add_app("acme", AppEntry(name="A", command="a"))

    store.move_app("acme", 0, 5)
    store.move_app("nobody", 0, 0)

    assert [a.name for a in store.clients[0].apps] == ["A"]


def test_update_client_edits_fields_in_place(tmp_path):
    store = ConfigStore(path=tmp_path / "config.json")
    store.add_client(ClientEntry(name="Acme", description="old", username="acme"))

    store.update_client("acme", "Acme Corp", "new", "acme", "/logo.png")

    reloaded = ConfigStore(path=store.path)
    assert len(reloaded.clients) == 1
    client = reloaded.clients[0]
    assert client.name == "Acme Corp"
    assert client.description == "new"
    assert client.username == "acme"
    assert client.logo_path == "/logo.png"


def test_update_client_rename_keeps_apps_attached(tmp_path):
    store = ConfigStore(path=tmp_path / "config.json")
    store.add_client(ClientEntry(name="Acme", description="", username="acme"))
    store.add_app("acme", AppEntry(name="Terminal", command="term"))

    store.update_client("acme", "Acme", "", "acme2", None)

    assert store.get_client("acme") is None
    renamed = store.get_client("acme2")
    assert renamed is not None
    assert [a.name for a in renamed.apps] == ["Terminal"]


def test_update_client_unknown_username_raises(tmp_path):
    store = ConfigStore(path=tmp_path / "config.json")
    try:
        store.update_client("nobody", "X", "", "nobody2", None)
    except KeyError:
        pass
    else:
        raise AssertionError("expected KeyError for unknown client")


def test_remove_client(tmp_path):
    store = ConfigStore(path=tmp_path / "config.json")
    store.add_client(ClientEntry(name="Acme", description="", username="acme"))
    store.add_client(ClientEntry(name="Beta", description="", username="beta"))

    store.remove_client("acme")

    reloaded = ConfigStore(path=store.path)
    usernames = [c.username for c in reloaded.clients]
    assert usernames == ["beta"]


def test_window_state_round_trip(tmp_path):
    store = ConfigStore(path=tmp_path / "config.json")
    store.set_window_state(WindowState(x=10, y=20, width=800, height=600, monitor_name="DP-1"))

    reloaded = ConfigStore(path=store.path)
    assert reloaded.window_state == WindowState(x=10, y=20, width=800, height=600, monitor_name="DP-1")


def test_corrupt_config_falls_back_to_empty(tmp_path):
    path = tmp_path / "config.json"
    path.write_text("{not valid json", encoding="utf-8")

    store = ConfigStore(path=path)
    assert store.clients == []
    assert store.window_state is None


def test_save_creates_missing_parent_dir(tmp_path):
    path = tmp_path / "nested" / "dir" / "config.json"
    store = ConfigStore(path=path)
    store.add_client(ClientEntry(name="Acme", description="", username="acme"))
    assert path.exists()


def test_save_leaves_no_leftover_temp_files(tmp_path):
    store = ConfigStore(path=tmp_path / "config.json")
    store.add_client(ClientEntry(name="Acme", description="", username="acme"))

    leftovers = list(tmp_path.glob(".config-*.tmp"))
    assert leftovers == []
