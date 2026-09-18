import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Dialogs

// Themed "add customer" dialog: logo, name, description, username-to-create
// (live-validated against the system's existing users/groups).
Popup {
    id: root

    property var anchorItem: null
    property bool creationFailed: false

    modal: true
    focus: true
    width: 420 * Theme.uiScale
    padding: 24 * Theme.uiScale
    x: anchorItem ? (anchorItem.width - width) / 2 : 0
    y: anchorItem ? (anchorItem.height - height) / 2 : 0

    background: Rectangle {
        color: Theme.surface
        radius: Theme.cornerRadius
        border.color: Theme.surfaceGlass
        border.width: 1
    }

    function reset() {
        nameField.text = ""
        nameField.touched = false
        descriptionField.text = ""
        usernameField.text = ""
        usernameField.touched = false
        logoField.text = ""
        creationFailed = false
    }

    onOpened: reset()

    ColumnLayout {
        width: parent.width
        spacing: Theme.spacing

        Text {
            text: "Add client"
            color: Theme.textPrimary
            font.pixelSize: Theme.fontSizeLarge
            font.bold: true
        }

        RowLayout {
            Layout.fillWidth: true
            ValidatedTextField {
                id: logoField
                Layout.fillWidth: true
                placeholderText: "Logo image path"
            }
            Button {
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
            errorText: "That username or group already exists."
            validator: (t) => t.trim().length > 0 && !usernameChecker.isTaken(t)
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
            Layout.alignment: Qt.AlignLeft
            spacing: Theme.spacing

            Button {
                text: "Cancel"
                onClicked: root.close()
            }
            Button {
                text: "Add"
                enabled: nameField.text.length > 0 && nameField.isValid
                    && usernameField.text.length > 0 && usernameField.isValid
                onClicked: {
                    // Creating the Linux user requires root (pkexec) — only
                    // persist the client once that actually succeeded, so
                    // config never references a user that doesn't exist.
                    root.creationFailed = false
                    if (clientProvisioner.createLinuxUser(usernameField.text)) {
                        clientModel.addClient(nameField.text, descriptionField.text, usernameField.text, logoField.text)
                        root.close()
                    } else {
                        root.creationFailed = true
                    }
                }
            }
        }
    }

    FileDialog {
        id: logoFileDialog
        title: "Choose logo image"
        nameFilters: ["Images (*.png *.jpg *.jpeg *.svg)"]
        onAccepted: logoField.text = selectedFile.toString().replace("file://", "")
    }
}
