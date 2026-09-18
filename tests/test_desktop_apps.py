from __future__ import annotations

from clientdeck.desktop_apps import _default_search_dirs, discover_desktop_apps


def _write_desktop_file(directory, filename, content):
    directory.mkdir(parents=True, exist_ok=True)
    (directory / filename).write_text(content, encoding="utf-8")


def test_discovers_basic_app(tmp_path):
    apps_dir = tmp_path / "applications"
    _write_desktop_file(
        apps_dir,
        "editor.desktop",
        "[Desktop Entry]\nType=Application\nName=Editor\nExec=editor %F\nIcon=editor-icon\n",
    )

    apps = discover_desktop_apps(search_dirs=[str(apps_dir)])

    assert len(apps) == 1
    assert apps[0].name == "Editor"
    assert apps[0].exec_command == "editor"
    assert apps[0].icon == "editor-icon"


def test_skips_nodisplay_and_hidden(tmp_path):
    apps_dir = tmp_path / "applications"
    _write_desktop_file(
        apps_dir, "hidden1.desktop", "[Desktop Entry]\nType=Application\nName=H1\nExec=h1\nNoDisplay=true\n"
    )
    _write_desktop_file(
        apps_dir, "hidden2.desktop", "[Desktop Entry]\nType=Application\nName=H2\nExec=h2\nHidden=true\n"
    )
    _write_desktop_file(apps_dir, "visible.desktop", "[Desktop Entry]\nType=Application\nName=Visible\nExec=v\n")

    apps = discover_desktop_apps(search_dirs=[str(apps_dir)])

    assert [a.name for a in apps] == ["Visible"]


def test_skips_non_application_types(tmp_path):
    apps_dir = tmp_path / "applications"
    _write_desktop_file(apps_dir, "link.desktop", "[Desktop Entry]\nType=Link\nName=SomeLink\nURL=http://example.com\n")

    apps = discover_desktop_apps(search_dirs=[str(apps_dir)])

    assert apps == []


def test_skips_entries_missing_type_entirely(tmp_path):
    # Type= is required by the Desktop Entry Specification — a missing key
    # is not the same as an explicit Type=Application, and must not be
    # treated as one.
    apps_dir = tmp_path / "applications"
    _write_desktop_file(apps_dir, "no-type.desktop", "[Desktop Entry]\nName=NoType\nExec=no-type\n")

    apps = discover_desktop_apps(search_dirs=[str(apps_dir)])

    assert apps == []


def test_higher_priority_dir_overrides_lower(tmp_path):
    low_priority = tmp_path / "low"
    high_priority = tmp_path / "high"
    _write_desktop_file(low_priority, "app.desktop", "[Desktop Entry]\nType=Application\nName=Low\nExec=low\n")
    _write_desktop_file(high_priority, "app.desktop", "[Desktop Entry]\nType=Application\nName=High\nExec=high\n")

    # search_dirs is documented as lowest-priority first.
    apps = discover_desktop_apps(search_dirs=[str(low_priority), str(high_priority)])

    assert len(apps) == 1
    assert apps[0].name == "High"


def test_missing_directories_are_ignored(tmp_path):
    apps = discover_desktop_apps(search_dirs=[str(tmp_path / "does-not-exist")])
    assert apps == []


def test_working_dir_from_path_key(tmp_path):
    apps_dir = tmp_path / "applications"
    _write_desktop_file(
        apps_dir,
        "tool.desktop",
        "[Desktop Entry]\nType=Application\nName=Tool\nExec=tool\nPath=/opt/tool\n",
    )

    apps = discover_desktop_apps(search_dirs=[str(apps_dir)])

    assert apps[0].working_dir == "/opt/tool"


def test_results_sorted_by_name_case_insensitive(tmp_path):
    apps_dir = tmp_path / "applications"
    _write_desktop_file(apps_dir, "b.desktop", "[Desktop Entry]\nType=Application\nName=banana\nExec=b\n")
    _write_desktop_file(apps_dir, "a.desktop", "[Desktop Entry]\nType=Application\nName=Apple\nExec=a\n")

    apps = discover_desktop_apps(search_dirs=[str(apps_dir)])

    assert [a.name for a in apps] == ["Apple", "banana"]


def test_default_search_dirs_orders_home_last(monkeypatch):
    monkeypatch.setenv("XDG_DATA_DIRS", "/usr/local/share:/usr/share")
    monkeypatch.setenv("XDG_DATA_HOME", "/home/tester/.local/share")

    dirs = _default_search_dirs()

    assert dirs[-1] == "/home/tester/.local/share/applications"
    assert dirs[0] == "/usr/share/applications"
    assert dirs[1] == "/usr/local/share/applications"
