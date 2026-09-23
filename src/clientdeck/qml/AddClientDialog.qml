import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Dialogs
import QtQuick.Window

// Themed "add customer" dialog: logo, name, description, username-to-create
// (an already-existing username is confirmed with the user at submit
// time, not flagged live — see [119]).
//
// Real top-level Window (not Popup); `flags` must match Main.qml's own
// exactly. See docs/comments-details.md [40].
Window {
    id: root

    property var anchorWindow: null
    property bool creationFailed: false
    property string logoPath: ""

    flags: Qt.FramelessWindowHint | Qt.Window
    modality: Qt.WindowModal
    color: "transparent"
    visible: false
    width: 420 * Theme.uiScale
    height: contentColumn.implicitHeight + dialogPadding * 2

    readonly property real dialogPadding: 24 * Theme.uiScale

    // x/y set once, imperatively, not as a live binding — see [41].
    function open() {
        reset()
        if (anchorWindow) {
            root.x = anchorWindow.x + (anchorWindow.width - root.width) / 2
            root.y = anchorWindow.y + (anchorWindow.height - root.height) / 2
        }
        root.visible = true
    }
    function close() {
        root.visible = false
    }

    function reset() {
        nameField.text = ""
        nameField.touched = false
        descriptionField.text = ""
        usernameField.text = ""
        usernameField.touched = false
        root.logoPath = ""
        creationFailed = false
    }

    // Entry point for the "Add" button — see [119].
    function submitAdd() {
        root.creationFailed = false
        if (usernameChecker.isTaken(usernameField.text)) {
            useExistingUserConfirm.open()
            return
        }
        root.createNewUserAndAddClient()
    }

    // Only persist once user creation succeeds — see [43].
    function createNewUserAndAddClient() {
        if (clientProvisioner.createLinuxUser(usernameField.text)) {
            root.addClientEntry()
        } else {
            root.creationFailed = true
        }
    }

    // No user creation at all — the account already exists — see [119].
    function useExistingUserAndAddClient() {
        root.addClientEntry()
    }

    function addClientEntry() {
        clientModel.addClient(nameField.text, descriptionField.text, usernameField.text, root.logoPath)
        root.close()
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
            id: contentColumn
            anchors.fill: parent
            anchors.margins: root.dialogPadding
            spacing: Theme.spacing

            Text {
                text: "Add client"
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSizeLarge
                font.bold: true
            }

            RowLayout {
                Layout.fillWidth: true
                // Theme-token-derived height, set as both preferredHeight
                // and minimumHeight — see docs/comments-details.md [42].
                Layout.preferredHeight: Theme.smallIconButtonSize * 2
                Layout.minimumHeight: Theme.smallIconButtonSize * 2
                spacing: Theme.spacing

                // Shown until a logo is picked, so an empty preview
                // doesn't read as broken/missing.
                Text {
                    visible: root.logoPath === ""
                    text: "No logo selected…"
                    font.italic: true
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeMedium
                    verticalAlignment: Text.AlignVCenter
                    Layout.fillHeight: true
                }
                // Fills the row height; width follows the image's own aspect ratio.
                Image {
                    visible: root.logoPath !== ""
                    source: root.logoPath
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

            ValidatedTextField {
                id: nameField
                Layout.fillWidth: true
                placeholderText: "Name"
                validator: (t) => t.trim().length > 0
                errorText: "Name is required."
            }

            ValidatedTextField {
                id: descriptionField
                Layout.fillWidth: true
                placeholderText: "Description"
            }

            ValidatedTextField {
                id: usernameField
                Layout.fillWidth: true
                placeholderText: "Username to create"
                errorText: "Username is required."
                // An already-taken username is no longer flagged here as
                // invalid — see [119]: confirmed with the user at submit
                // time instead, via useExistingUserConfirm below.
                validator: (t) => t.trim().length > 0
            }

            Text {
                visible: root.creationFailed
                text: "Failed to create the Linux user account. Check the system logs and try again."
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
                    text: "Add"
                    enabled: nameField.text.length > 0 && nameField.isValid
                        && usernameField.text.length > 0 && usernameField.isValid
                    onClicked: root.submitAdd()
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

    // Anchored to this dialog, not the main window — same reasoning as [48].
    ConfirmDialog {
        id: useExistingUserConfirm
        anchorWindow: root
        message: "A Linux user or group named \"" + usernameField.text
            + "\" already exists. Use it as this client's account?"
        confirmLabel: "Use existing"
        cancelLabel: "Cancel"
        onConfirmed: root.useExistingUserAndAddClient()
    }
}
