import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Window

// The per-row "+" dialog: pick an existing discovered .desktop app, or
// switch to manual/custom entry mode (name, command, working dir, su
// wrapping toggle, icon).
//
// Real top-level Window with flags matching Main.qml — see docs/comments-details.md [40].
Window {
    id: root

    property var anchorWindow: null
    property string targetUsername: ""
    property bool manualMode: false
    property var discovered: []
    property string searchText: ""

    // Case-insensitive substring match on name — the whole point of the
    // search box below the "Add app" title.
    readonly property var filteredApps: searchText.trim().length === 0
        ? discovered
        : discovered.filter((a) => a.name.toLowerCase().includes(searchText.trim().toLowerCase()))

    readonly property real dialogPadding: 24 * Theme.uiScale

    flags: Qt.FramelessWindowHint | Qt.Window
    modality: Qt.WindowModal
    color: "transparent"
    visible: false
    width: 460 * Theme.uiScale
    height: 480 * Theme.uiScale

    // x/y set once, imperatively, not as a live binding — see [41].
    function open() {
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
        if (anchorWindow) {
            root.x = anchorWindow.x + (anchorWindow.width - root.width) / 2
            root.y = anchorWindow.y + (anchorWindow.height - root.height) / 2
        }
        root.visible = true
    }
    function close() {
        root.visible = false
    }

    Shortcut {
        sequence: "Escape"
        onActivated: root.close()
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.surface
        radius: Theme.cornerRadius
        border.color: Theme.surfaceGlass
        border.width: 1

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: root.dialogPadding
            spacing: Theme.spacing

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "Add application"
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontSizeLarge
                    font.bold: true
                    Layout.fillWidth: true
                }
                ThemedButton {
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

            // ScrollView, not a bare ListView, for a visible scrollbar — see [49].
            ScrollView {
                visible: !root.manualMode
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                ListView {
                    model: root.filteredApps
                    delegate: ItemDelegate {
                        id: appDelegate
                        width: ListView.view.width
                        text: modelData.name
                        hoverEnabled: true

                        // Full themed override — see docs/comments-details.md [50].
                        background: Rectangle {
                            color: appDelegate.hovered ? Theme.surfaceHover : "transparent"
                        }

                        contentItem: RowLayout {
                            spacing: Theme.spacing

                            // Missing/unresolvable icon shows nothing — see [51].
                            Image {
                                Layout.preferredWidth: Theme.fontSizeLarge
                                Layout.preferredHeight: Theme.fontSizeLarge
                                visible: source !== ""
                                source: modelData.icon
                                    ? (modelData.icon.startsWith("/") ? modelData.icon : "image://theme/" + modelData.icon)
                                    : ""
                                fillMode: Image.PreserveAspectFit
                            }
                            Text {
                                text: appDelegate.text
                                color: Theme.textPrimary
                                font.pixelSize: Theme.fontSizeMedium
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }

                        onClicked: {
                            clientModel.addAppToClient(
                                root.targetUsername, modelData.name, modelData.command, true, modelData.workingDir,
                                modelData.icon || "")
                            root.close()
                        }
                    }
                }
            }

            RowLayout {
                // Pick-existing needs its own Cancel too — see [52].
                visible: !root.manualMode
                Layout.alignment: Qt.AlignRight
                spacing: Theme.spacing

                ThemedButton {
                    text: "Cancel"
                    onClicked: root.close()
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
                    // Only way to set an icon for a manual app — see [53].
                    placeholderText: "Icon name or path (optional)"
                }
                CheckBox {
                    id: manualUseSu
                    text: "Run as su - <username> -c '...'"
                    checked: true

                    // Same theming issue/fix as the ItemDelegate above — see [50].
                    contentItem: Text {
                        text: manualUseSu.text
                        color: Theme.textPrimary
                        font.pixelSize: Theme.fontSizeMedium
                        verticalAlignment: Text.AlignVCenter
                        leftPadding: manualUseSu.indicator.width + manualUseSu.spacing
                    }

                    indicator: Rectangle {
                        implicitWidth: Theme.fontSizeLarge
                        implicitHeight: Theme.fontSizeLarge
                        x: manualUseSu.leftPadding
                        y: parent.height / 2 - height / 2
                        radius: Theme.cornerRadius / 4
                        color: manualUseSu.checked ? Theme.accent : Theme.surfaceGlass
                        border.width: 1
                        border.color: Theme.accent

                        Text {
                            anchors.centerIn: parent
                            text: "✓"
                            color: Theme.textPrimary
                            visible: manualUseSu.checked
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }
                }
                Item { Layout.fillHeight: true }
                RowLayout {
                    Layout.alignment: Qt.AlignRight
                    spacing: Theme.spacing

                    ThemedButton {
                        text: "Cancel"
                        onClicked: root.close()
                    }
                    ThemedButton {
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
}
