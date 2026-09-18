import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Dialogs

// Themed "modify client" dialog, opened by double-clicking a client's logo
// (see ClientRow.qml). Same fields as AddClientDialog, pre-filled with the
// client's current values, plus the rename-aware flow described in
// CLAUDE.md's "Modifying a client" section: changing the username creates
// a new Linux user for it, then asks (via ConfirmDialog) whether the old
// user's content should be deleted or kept.
Popup {
    id: root

    property var anchorItem: null
    property string originalUsername: ""
    property string logoPath: ""
    property bool modificationFailed: false

    // Shared left column width for every field row's label, so "Logo",
    // "Name", "Description", and "Username" line up and every input starts
    // at the same x — a plain constant rather than a computed max-of-
    // implicitWidths, since these four labels are fixed, known strings.
    readonly property real fieldLabelWidth: 90 * Theme.uiScale

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

    // Called by Main.qml right before open() with the client's current
    // values — a plain function rather than onOpened-driven reset (like
    // AddClientDialog's) since there's no other way to get per-client data
    // into this shared dialog instance.
    function openFor(username, name, description, logoPath) {
        root.originalUsername = username
        nameField.text = name
        nameField.touched = false
        descriptionField.text = description
        descriptionField.touched = false
        usernameField.text = username
        usernameField.touched = false
        root.logoPath = logoPath || ""
        root.modificationFailed = false
        root.open()
    }

    function finishUpdate(newUsername) {
        clientModel.updateClient(root.originalUsername, nameField.text, descriptionField.text, newUsername, root.logoPath)
        root.close()
    }

    ColumnLayout {
        width: parent.width
        spacing: Theme.spacing

        // Header: bigger logo + bold client name, so it's obvious at a
        // glance which client this dialog is editing. Bound to the same
        // live values the fields below edit, rather than a static
        // snapshot, so it previews the change as you type/browse.
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing

            Image {
                Layout.preferredWidth: Theme.hugeIconButtonSize
                Layout.preferredHeight: Theme.hugeIconButtonSize
                source: root.logoPath
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
            spacing: Theme.spacing

            Text {
                text: "Logo"
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeBody
                Layout.preferredWidth: root.fieldLabelWidth
            }
            // Preview of the currently-selected logo, in place of showing
            // its raw path — sized to the Browse button's own height so it
            // reads as a compact thumbnail next to it, not an oversized
            // image throwing off the row.
            Image {
                Layout.preferredWidth: browseButton.height
                Layout.preferredHeight: browseButton.height
                source: root.logoPath
                fillMode: Image.PreserveAspectFit
            }
            Item { Layout.fillWidth: true }
            Button {
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
                // Keeping the same username the client already has must not
                // flag itself as "taken" — only a genuinely different,
                // already-in-use name is invalid.
                validator: (t) => t.trim().length > 0
                    && (t === root.originalUsername || !usernameChecker.isTaken(t))
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
            Layout.alignment: Qt.AlignLeft
            spacing: Theme.spacing

            Button {
                text: "Cancel"
                onClicked: root.close()
            }
            Button {
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
                    // Renaming requires a new Linux user for the new
                    // username — only proceed with the config update (and
                    // ask about the old one's content) once that actually
                    // succeeded, same "don't persist ahead of reality"
                    // rule AddClientDialog follows for a brand-new client.
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

    FileDialog {
        id: logoFileDialog
        title: "Choose logo image"
        nameFilters: ["Images (*.png *.jpg *.jpeg *.svg)"]
        onAccepted: root.logoPath = selectedFile.toString().replace("file://", "")
    }

    ConfirmDialog {
        id: deleteOldContentConfirm
        anchorItem: root.anchorItem
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
