import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Dialogs
import QtQuick.Window

// Themed "modify client" dialog, opened by right-clicking a client's logo
// (see ClientRow.qml). Same fields as AddClientDialog, pre-filled with the
// client's current values, plus the rename-aware flow described in
// CLAUDE.md's "Modifying a client" section: changing the username creates
// a new Linux user for it, then asks (via ConfirmDialog) whether the old
// user's content should be deleted or kept.
//
// Real top-level Window with flags matching Main.qml — see docs/comments-details.md [40].
Window {
    id: root

    property var anchorWindow: null
    property string originalUsername: ""
    property string logoPath: ""
    property bool modificationFailed: false

    // Fixed constant, so every field row's label lines up — see [44].
    readonly property real fieldLabelWidth: 90 * Theme.uiScale
    readonly property real dialogPadding: 24 * Theme.uiScale

    flags: Qt.FramelessWindowHint | Qt.Window
    modality: Qt.WindowModal
    color: "transparent"
    visible: false
    width: 480 * Theme.uiScale
    height: contentColumn.implicitHeight + dialogPadding * 2

    // x/y set once, imperatively, not as a live binding — see [41].
    function open() {
        if (anchorWindow) {
            root.x = anchorWindow.x + (anchorWindow.width - root.width) / 2
            root.y = anchorWindow.y + (anchorWindow.height - root.height) / 2
        }
        root.visible = true
        // Explicit activation request — see [123].
        root.requestActivate()
    }
    function close() { root.visible = false }

    // Plain function, not onOpened-driven reset — see [45].
    function openFor(username, name, description, logoPath) {
        root.originalUsername = username
        nameField.text = name
        nameField.touched = false
        descriptionField.text = description
        descriptionField.touched = false
        usernameField.text = username
        usernameField.touched = false
        root.logoPath = logoPath || ""
        advancedSection.expanded = false
        supportDbusCheck.checked = true
        supportDisplayCheck.checked = true
        singleSshAgentCheck.checked = true
        promptSetting.reset()
        root.modificationFailed = false
        root.open()
    }

    function finishUpdate(newUsername) {
        clientModel.updateClient(root.originalUsername, nameField.text, descriptionField.text, newUsername, root.logoPath)
        root.close()
    }

    // Only while this window is focused — nested dialogs' Escape shortcuts
    // would otherwise all match at once and cancel out; see [137].
    Shortcut {
        sequence: "Escape"
        enabled: focusTracker.focusWindow === root
        onActivated: root.close()
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

            // Header preview, bound to live field values — see [46].
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing

                Image {
                    Layout.preferredWidth: Theme.hugeIconButtonSize
                    Layout.preferredHeight: Theme.hugeIconButtonSize
                    // Themed placeholder when unset — see [125].
                    source: root.logoPath || Theme.noItemSource
                    fillMode: Image.PreserveAspectFit
                }
                Text {
                    text: nameField.text
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontSizeLarge
                    font.bold: true
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }

            RowLayout {
                Layout.fillWidth: true
                // Theme-token-derived height, both preferredHeight and
                // minimumHeight — see docs/comments-details.md [47].
                Layout.preferredHeight: Theme.smallIconButtonSize * 2
                Layout.minimumHeight: Theme.smallIconButtonSize * 2
                spacing: Theme.spacing

                Text {
                    text: "Logo"
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeBody
                    Layout.preferredWidth: root.fieldLabelWidth
                }
                // Fills the row height; width follows the image's own
                // aspect ratio. Falls back to the themed no-item
                // placeholder when unset — see [125].
                Image {
                    source: root.logoPath || Theme.noItemSource
                    fillMode: Image.PreserveAspectFit
                    Layout.preferredHeight: Theme.smallIconButtonSize * 2
                    Layout.preferredWidth: implicitHeight > 0
                        ? (Theme.smallIconButtonSize * 2) * (implicitWidth / implicitHeight)
                        : Theme.smallIconButtonSize * 2
                }
                Item { Layout.fillWidth: true }
                ThemedButton {
                    id: browseButton
                    text: "Browse…"
                    onClicked: logoFileDialog.open()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing

                Text {
                    text: "Name"
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeBody
                    Layout.preferredWidth: root.fieldLabelWidth
                }
                ValidatedTextField {
                    id: nameField
                    Layout.fillWidth: true
                    validator: (t) => t.trim().length > 0
                    errorText: "Name is required."
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing

                Text {
                    text: "Description"
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeBody
                    Layout.preferredWidth: root.fieldLabelWidth
                }
                ValidatedTextField {
                    id: descriptionField
                    Layout.fillWidth: true
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing

                Text {
                    text: "Username"
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeBody
                    Layout.preferredWidth: root.fieldLabelWidth
                }
                ValidatedTextField {
                    id: usernameField
                    Layout.fillWidth: true
                    errorText: "That username or group already exists."
                    // The client's own current username must not self-flag as taken.
                    validator: (t) => t.trim().length > 0
                        && (t === root.originalUsername || !usernameChecker.isTaken(t))
                }
            }

            // Same options as AddClientDialog's, body aligned with the
            // field column — not yet acted on or stored, see [129].
            ThemedExpander {
                id: advancedSection
                Layout.fillWidth: true
                title: "Advanced"
                contentIndent: root.fieldLabelWidth + Theme.spacing

                ThemedCheckBox {
                    id: supportDbusCheck
                    text: "Support DBus"
                    checked: true
                }
                ThemedCheckBox {
                    id: supportDisplayCheck
                    text: "Support Wayland/X"
                    checked: true
                }
                ThemedCheckBox {
                    id: singleSshAgentCheck
                    text: "Single SSH Agent"
                    checked: true
                }
                PromptSetting {
                    id: promptSetting
                    Layout.fillWidth: true
                    username: usernameField.text
                    anchorWindow: root
                }
            }

            Text {
                visible: root.modificationFailed
                text: "Failed to create the new Linux user account. Check the system logs and try again."
                color: Theme.danger
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: Theme.spacing

                ThemedButton {
                    text: "Cancel"
                    onClicked: root.close()
                }
                ThemedButton {
                    text: "Apply"
                    enabled: nameField.text.length > 0 && nameField.isValid
                        && usernameField.text.length > 0 && usernameField.isValid
                    onClicked: {
                        root.modificationFailed = false
                        if (usernameField.text === root.originalUsername) {
                            // No rename — nothing Linux-user-related to do.
                            root.finishUpdate(usernameField.text)
                            return
                        }
                        // Only proceed once the new user actually exists — see [43].
                        if (clientProvisioner.createLinuxUser(usernameField.text)) {
                            deleteOldContentConfirm.pendingNewUsername = usernameField.text
                            deleteOldContentConfirm.open()
                        } else {
                            root.modificationFailed = true
                        }
                    }
                }
            }
        }
    }

    FileDialog {
        id: logoFileDialog
        title: "Choose logo image"
        nameFilters: ["Images (*.png *.jpg *.jpeg *.svg)"]
        onAccepted: root.logoPath = selectedFile.toString().replace("file://", "")
    }

    ConfirmDialog {
        id: deleteOldContentConfirm
        // Anchored to this dialog, not the main window — see [48].
        anchorWindow: root
        property string pendingNewUsername: ""
        message: "The client is being renamed to a new user. Delete the original user's content ("
            + root.originalUsername + ")? This cannot be undone."
        confirmLabel: "Delete"
        cancelLabel: "Keep"
        onConfirmed: {
            clientProvisioner.deleteLinuxUser(root.originalUsername)
            root.finishUpdate(pendingNewUsername)
        }
        onCancelled: {
            root.finishUpdate(pendingNewUsername)
        }
    }
}
