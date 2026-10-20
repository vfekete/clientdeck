import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import QtQuick.Layouts
import QtQuick.Window

// The per-row "+" dialog: a custom-command form (icon, name, command,
// working dir, su wrapping) by default; "Pick existing…" switches to the
// discovered .desktop apps list, and picking one fills the form rather
// than adding it directly — see docs/comments-details.md [139].
// Also the "edit application" dialog (right-click an app button):
// pre-filled, Apply instead of Add, plus a confirmed Remove — see [140].
//
// Real top-level Window with flags matching Main.qml — see [40].
Window {
    id: root

    property var anchorWindow: null
    property string targetUsername: ""
    // Index of the app being edited; -1 = adding a new one.
    property int editIndex: -1
    // The edited app's name as it was when the dialog opened.
    property string editAppName: ""
    readonly property bool editMode: editIndex >= 0
    property bool pickMode: false
    property var discovered: []
    property string searchText: ""
    // Absolute image path or icon-theme name; "" = none.
    property string iconValue: ""
    // Name of the discovered app the form is based on; "" = none.
    property string pickedAppName: ""
    // "Run as su" state from before the first pick, restored by Clear.
    property bool useSuBeforePick: true

    // Case-insensitive substring match on name.
    readonly property var filteredApps: searchText.trim().length === 0
        ? discovered
        : discovered.filter((a) => a.name.toLowerCase().includes(searchText.trim().toLowerCase()))

    readonly property real dialogPadding: 24 * Theme.uiScale

    flags: Qt.FramelessWindowHint | Qt.Window
    modality: Qt.WindowModal
    color: "transparent"
    visible: false
    width: 460 * Theme.uiScale
    // Picker: fixed (the list scrolls inside); form: at least that, growing
    // to fit — never the list's own implicit height, see [139].
    readonly property real baseHeight: 480 * Theme.uiScale
    height: pickMode ? baseHeight : Math.max(baseHeight, contentColumn.implicitHeight + dialogPadding * 2)

    // file:// URL from a dialog -> plain local path (percent-decoded).
    function urlToPath(url) {
        return decodeURIComponent(url.toString().replace(/^file:\/\//, ""))
    }

    function iconUrl(icon) {
        if (!icon)
            return ""
        return icon.startsWith("/") ? "file://" + icon : "image://theme/" + icon
    }

    // Add mode; for edit mode use openForEdit().
    function open() {
        root.editIndex = -1
        root.resetAndShow()
    }

    // `app`: one entry of ClientListModel's `apps` role.
    function openForEdit(username, index, app) {
        root.targetUsername = username
        root.editIndex = index
        root.resetAndShow()
        root.editAppName = app.name
        nameField.text = app.name
        nameField.touched = false
        commandField.text = app.command
        commandField.touched = false
        workdirField.text = app.workingDir || ""
        root.iconValue = app.icon || ""
        useSuCheck.checked = app.useSu
    }

    // Resets the form and shows the dialog.
    // x/y set once, imperatively, not as a live binding — see [41].
    function resetAndShow() {
        root.pickMode = false
        root.discovered = desktopAppsProvider.discover()
        searchField.text = ""
        nameField.text = ""
        nameField.touched = false
        commandField.text = ""
        commandField.touched = false
        workdirField.text = ""
        root.iconValue = ""
        root.pickedAppName = ""
        useSuCheck.checked = true
        if (anchorWindow) {
            root.x = anchorWindow.x + (anchorWindow.width - root.width) / 2
            root.y = anchorWindow.y + (anchorWindow.height - root.height) / 2
        }
        root.visible = true
        // Explicit activation request — see [123].
        root.requestActivate()
    }
    function close() {
        root.visible = false
    }

    // Fills the form from a discovered app; working dir is left as is.
    function applyPick(app) {
        if (!root.pickedAppName)
            root.useSuBeforePick = useSuCheck.checked
        nameField.text = app.name
        commandField.text = app.command
        root.iconValue = app.icon || ""
        useSuCheck.checked = true
        root.pickedAppName = app.name
        root.pickMode = false
    }

    // Undoes the pick: empties what it filled, restores "Run as su".
    function clearPick() {
        nameField.text = ""
        nameField.touched = false
        commandField.text = ""
        commandField.touched = false
        root.iconValue = ""
        useSuCheck.checked = root.useSuBeforePick
        root.pickedAppName = ""
    }

    // Only while this window is focused — nested dialogs' Escape shortcuts
    // would otherwise all match at once and cancel out; see [137].
    Shortcut {
        sequence: "Escape"
        enabled: focusTracker.focusWindow === root
        onActivated: root.pickMode ? (root.pickMode = false) : root.close()
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.surface
        radius: Theme.cornerRadius
        border.color: Theme.surfaceGlass
        border.width: 1

        ColumnLayout {
            id: contentColumn
            anchors.fill: parent
            anchors.margins: root.dialogPadding
            spacing: Theme.spacing

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: root.pickMode ? "Pick existing application" : (root.editMode ? "Edit application" : "Add application")
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontSizeLarge
                    font.bold: true
                    Layout.fillWidth: true
                }
                ThemedButton {
                    visible: !root.pickMode
                    text: "Pick existing…"
                    onClicked: {
                        searchField.text = ""
                        root.pickMode = true
                        searchField.forceActiveFocus()
                    }
                }
            }

            // ---- Custom command form (default) ----

            RowLayout {
                visible: !root.pickMode && root.pickedAppName !== ""
                Layout.fillWidth: true
                spacing: Theme.spacing

                Text {
                    text: "Based on: " + root.pickedAppName
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeBody
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                ThemedButton {
                    text: "Clear"
                    onClicked: root.clearPick()
                }
            }

            // Same layout as AddClientDialog's logo row — see [42], [139].
            RowLayout {
                visible: !root.pickMode
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.smallIconButtonSize * 2
                Layout.minimumHeight: Theme.smallIconButtonSize * 2
                spacing: Theme.spacing

                Item {
                    Layout.preferredWidth: Theme.smallIconButtonSize * 2
                    Layout.preferredHeight: Theme.smallIconButtonSize * 2

                    Image {
                        id: iconPreview
                        anchors.fill: parent
                        source: root.iconUrl(root.iconValue)
                        sourceSize.width: width
                        sourceSize.height: height
                        fillMode: Image.PreserveAspectFit
                        visible: root.iconValue !== "" && status === Image.Ready && implicitWidth > 0
                    }
                    // Themed placeholder while no icon is set or it can't be loaded — see [126].
                    Image {
                        anchors.fill: parent
                        source: Theme.noItemSource
                        fillMode: Image.PreserveAspectFit
                        visible: !iconPreview.visible
                    }
                }
                Item { Layout.fillWidth: true }
                ThemedButton {
                    text: "Browse…"
                    onClicked: iconFileDialog.open()
                }
            }

            ValidatedTextField {
                id: nameField
                visible: !root.pickMode
                Layout.fillWidth: true
                placeholderText: "Name"
                validator: (t) => t.trim().length > 0
                errorText: "Name is required."
            }
            ValidatedTextField {
                id: commandField
                visible: !root.pickMode
                Layout.fillWidth: true
                placeholderText: "Launch command"
                validator: (t) => t.trim().length > 0
                errorText: "Launch command is required."
            }
            RowLayout {
                visible: !root.pickMode
                Layout.fillWidth: true
                spacing: Theme.spacing

                ValidatedTextField {
                    id: workdirField
                    Layout.fillWidth: true
                    placeholderText: "Working directory (optional)"
                }
                // Directory picker, not a file dialog — see [141].
                ThemedButton {
                    text: "Browse…"
                    onClicked: {
                        if (workdirField.text.startsWith("/"))
                            workdirDialog.currentFolder = "file://" + workdirField.text
                        workdirDialog.open()
                    }
                }
            }
            ThemedCheckBox {
                id: useSuCheck
                visible: !root.pickMode
                text: "Run as su - <username> -c '...'"
                checked: true
            }
            Item {
                visible: !root.pickMode
                Layout.fillHeight: true
            }
            RowLayout {
                visible: !root.pickMode
                Layout.fillWidth: true
                spacing: Theme.spacing

                ThemedButton {
                    visible: root.editMode
                    danger: true
                    text: "Remove"
                    onClicked: removeConfirm.open()
                }
                Item { Layout.fillWidth: true }
                ThemedButton {
                    text: "Cancel"
                    onClicked: root.close()
                }
                ThemedButton {
                    text: root.editMode ? "Apply" : "Add"
                    enabled: nameField.text.length > 0 && nameField.isValid
                        && commandField.text.length > 0 && commandField.isValid
                    onClicked: {
                        if (root.editMode)
                            clientModel.updateApp(
                                root.targetUsername, root.editIndex, nameField.text, commandField.text,
                                useSuCheck.checked, workdirField.text, root.iconValue)
                        else
                            clientModel.addAppToClient(
                                root.targetUsername, nameField.text, commandField.text,
                                useSuCheck.checked, workdirField.text, root.iconValue)
                        root.close()
                    }
                }
            }

            // ---- Pick existing ----

            ThemedSearchField {
                id: searchField
                visible: root.pickMode
                Layout.fillWidth: true
                hintText: "Application name"
                onTextChanged: root.searchText = text
            }

            // ScrollView, not a bare ListView, for a visible scrollbar — see [49].
            ScrollView {
                visible: root.pickMode
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

                        // Full themed override — see [50].
                        background: Rectangle {
                            color: appDelegate.hovered ? Theme.surfaceHover : "transparent"
                        }

                        contentItem: RowLayout {
                            spacing: Theme.spacing

                            // Missing/unresolvable icon falls back to the
                            // themed no-item placeholder — see [51], [126].
                            Image {
                                id: listIcon
                                Layout.preferredWidth: Theme.fontSizeLarge
                                Layout.preferredHeight: Theme.fontSizeLarge
                                source: modelData.icon ? root.iconUrl(modelData.icon) : Theme.noItemSource
                                fillMode: Image.PreserveAspectFit

                                Image {
                                    anchors.fill: parent
                                    source: Theme.noItemSource
                                    fillMode: Image.PreserveAspectFit
                                    visible: listIcon.status === Image.Error
                                        || (listIcon.status === Image.Ready && listIcon.implicitWidth === 0)
                                }
                            }
                            Text {
                                text: appDelegate.text
                                color: Theme.textPrimary
                                font.pixelSize: Theme.fontSizeMedium
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }

                        onClicked: root.applyPick(modelData)
                    }
                }
            }

            // Back to the form without picking anything — see [52].
            RowLayout {
                visible: root.pickMode
                Layout.alignment: Qt.AlignRight
                spacing: Theme.spacing

                ThemedButton {
                    text: "Cancel"
                    onClicked: root.pickMode = false
                }
            }
        }
    }

    // Remove must be confirmed — see [140]. Anchored to this dialog — see [48].
    ConfirmDialog {
        id: removeConfirm
        anchorWindow: root
        message: "Remove \"" + root.editAppName + "\" from this client? This cannot be undone."
        confirmLabel: "Remove"
        cancelLabel: "Cancel"
        onConfirmed: {
            clientModel.removeAppFromClient(root.targetUsername, root.editIndex)
            root.close()
        }
    }

    FileDialog {
        id: iconFileDialog
        title: "Choose application icon"
        nameFilters: ["Images (*.png *.jpg *.jpeg *.svg *.xpm)"]
        onAccepted: root.iconValue = root.urlToPath(selectedFile)
    }

    FolderDialog {
        id: workdirDialog
        title: "Choose working directory"
        onAccepted: workdirField.text = root.urlToPath(selectedFolder)
    }
}
