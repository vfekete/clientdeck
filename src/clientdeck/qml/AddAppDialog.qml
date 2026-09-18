import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// The per-row "+" dialog: pick an existing discovered .desktop app, or
// switch to manual/custom entry mode (name, command, working dir, su
// wrapping toggle, icon).
Popup {
    id: root

    property var anchorItem: null
    property string targetUsername: ""
    property bool manualMode: false
    property var discovered: []
    property string searchText: ""

    // Case-insensitive substring match on name — the whole point of the
    // search box below the "Add app" title.
    readonly property var filteredApps: searchText.trim().length === 0
        ? discovered
        : discovered.filter((a) => a.name.toLowerCase().includes(searchText.trim().toLowerCase()))

    modal: true
    focus: true
    width: 460 * Theme.uiScale
    height: 480 * Theme.uiScale
    padding: 24 * Theme.uiScale
    x: anchorItem ? (anchorItem.width - width) / 2 : 0
    y: anchorItem ? (anchorItem.height - height) / 2 : 0

    background: Rectangle {
        color: Theme.surface
        radius: Theme.cornerRadius
        border.color: Theme.surfaceGlass
        border.width: 1
    }

    onOpened: {
        manualMode = false
        discovered = desktopAppsProvider.discover()
        searchField.text = ""
        manualName.text = ""
        manualName.touched = false
        manualCommand.text = ""
        manualCommand.touched = false
        manualWorkdir.text = ""
        manualIcon.text = ""
        manualUseSu.checked = true
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.spacing

        RowLayout {
            Layout.fillWidth: true
            Text {
                text: "Add app"
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSizeLarge
                font.bold: true
                Layout.fillWidth: true
            }
            Button {
                text: root.manualMode ? "Pick existing" : "Custom command"
                onClicked: root.manualMode = !root.manualMode
            }
        }

        ThemedSearchField {
            id: searchField
            visible: !root.manualMode
            Layout.fillWidth: true
            hintText: "Application name"
            onTextChanged: root.searchText = text
        }

        ListView {
            visible: !root.manualMode
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: root.filteredApps
            delegate: ItemDelegate {
                width: ListView.view.width
                text: modelData.name
                // Discovered .desktop apps' Icon= value is either an
                // absolute path to an image file, or an icon-theme name
                // to resolve via the platform's icon theme — "if exists"
                // per the request: an empty/unresolvable one just shows
                // no icon rather than a broken-image placeholder (Image
                // silently renders nothing for an empty source, and
                // ItemDelegate's built-in icon+text layout collapses the
                // icon slot when there's nothing to show).
                icon.source: modelData.icon
                    ? (modelData.icon.startsWith("/") ? modelData.icon : "image://theme/" + modelData.icon)
                    : ""
                // Qt Quick Controls treats a non-transparent icon.color as
                // a request to recolor the icon as a flat-color mask
                // (meant for single-tone "symbolic" icons that should
                // inherit the current text color) — the Basic style's
                // ItemDelegate default isn't "transparent", so every real,
                // multi-color app icon was getting flattened to a solid
                // silhouette (white, since that's this delegate's default
                // text/icon color in dark mode). Disables that.
                icon.color: "transparent"
                onClicked: {
                    clientModel.addAppToClient(
                        root.targetUsername, modelData.name, modelData.command, true, modelData.workingDir,
                        modelData.icon || "")
                    root.close()
                }
            }
        }

        ColumnLayout {
            visible: root.manualMode
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.spacing

            ValidatedTextField {
                id: manualName
                Layout.fillWidth: true
                placeholderText: "Name"
                validator: (t) => t.trim().length > 0
                errorText: "Name is required."
            }
            ValidatedTextField {
                id: manualCommand
                Layout.fillWidth: true
                placeholderText: "Launch command"
                validator: (t) => t.trim().length > 0
                errorText: "Launch command is required."
            }
            ValidatedTextField {
                id: manualWorkdir
                Layout.fillWidth: true
                placeholderText: "Working directory (optional)"
            }
            ValidatedTextField {
                id: manualIcon
                Layout.fillWidth: true
                // Only way to get an icon on a manually-added app (e.g.
                // Docker, which typically has no launchable .desktop entry
                // to discover an icon from) — an absolute image path or an
                // icon-theme name, same as a discovered app's Icon= value.
                placeholderText: "Icon name or path (optional)"
            }
            CheckBox {
                id: manualUseSu
                text: "Run as su - <username> -c '...'"
                checked: true
            }
            Item { Layout.fillHeight: true }
            RowLayout {
                Layout.alignment: Qt.AlignLeft
                spacing: Theme.spacing

                Button {
                    text: "Cancel"
                    onClicked: root.close()
                }
                Button {
                    text: "Add"
                    enabled: manualName.text.length > 0 && manualName.isValid
                        && manualCommand.text.length > 0 && manualCommand.isValid
                    onClicked: {
                        clientModel.addAppToClient(
                            root.targetUsername, manualName.text, manualCommand.text,
                            manualUseSu.checked, manualWorkdir.text, manualIcon.text)
                        root.close()
                    }
                }
            }
        }
    }
}
