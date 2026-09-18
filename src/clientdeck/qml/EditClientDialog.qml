import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Dialogs
import QtQuick.Window

// Themed "modify client" dialog, opened by double-clicking a client's logo
// (see ClientRow.qml). Same fields as AddClientDialog, pre-filled with the
// client's current values, plus the rename-aware flow described in
// CLAUDE.md's "Modifying a client" section: changing the username creates
// a new Linux user for it, then asks (via ConfirmDialog) whether the old
// user's content should be deleted or kept.
//
// A real top-level Window, not a Popup — see AddClientDialog.qml's comment
// on why (`popupType: Popup.Window` still carries the Qt::Popup flag,
// which window managers exempt from normal drag-to-move) and on why
// `flags` below must match Main.qml's own exactly, not `Qt.Dialog`.
Window {
    id: root

    property var anchorWindow: null
    property string originalUsername: ""
    property string logoPath: ""
    property bool modificationFailed: false

    // Shared left column width for every field row's label, so "Logo",
    // "Name", "Description", and "Username" line up and every input starts
    // at the same x — a plain constant rather than a computed max-of-
    // implicitWidths, since these four labels are fixed, known strings.
    readonly property real fieldLabelWidth: 90 * Theme.uiScale
    readonly property real dialogPadding: 24 * Theme.uiScale

    flags: Qt.FramelessWindowHint | Qt.Window
    modality: Qt.WindowModal
    color: "transparent"
    visible: false
    width: 420 * Theme.uiScale
    height: contentColumn.implicitHeight + dialogPadding * 2

    // x/y set once here, imperatively — see AddClientDialog.qml's comment
    // on why this isn't a live binding on anchorWindow/width/height
    // anymore (it kept recentering the dialog every time uiScale changed
    // while open, discarding wherever the user had dragged it to).
    function open() {
        if (anchorWindow) {
            root.x = anchorWindow.x + (anchorWindow.width - root.width) / 2
            root.y = anchorWindow.y + (anchorWindow.height - root.height) / 2
        }
        root.visible = true
    }
    function close() { root.visible = false }

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
                // Theme.smallIconButtonSize * 2, not browseButton.height *
                // 2 — see AddClientDialog.qml's comment on this: a
                // Layout.preferredHeight binding reading a *sibling's*
                // live .height turned out to be unreliable on the first
                // layout pass specifically when the main window had other
                // content competing for it (confirmed via headless
                // testing). The same Theme token ThemedButton's own height
                // already derives from sidesteps that entirely. Also set
                // as minimumHeight — see AddClientDialog.qml's comment —
                // since a separate, related quirk (contentColumn's own
                // anchors.fill-derived height reading stale/negative on
                // that same first pass) meant preferredHeight alone could
                // still get shrunk below what was asked for.
                Layout.preferredHeight: Theme.smallIconButtonSize * 2
                Layout.minimumHeight: Theme.smallIconButtonSize * 2
                spacing: Theme.spacing

                Text {
                    text: "Logo"
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeBody
                    Layout.preferredWidth: root.fieldLabelWidth
                }
                // Placeholder text shown until a logo is actually picked —
                // an empty preview thumbnail read as broken/missing rather
                // than "nothing chosen yet".
                Text {
                    visible: root.logoPath === ""
                    text: "No logo selected…"
                    font.italic: true
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeMedium
                    verticalAlignment: Text.AlignVCenter
                    Layout.fillHeight: true
                }
                // Preview of the currently-selected logo, in place of
                // showing its raw path — height fills the row (now twice
                // the Browse button's own height), width follows from the
                // image's own aspect ratio rather than being forced square.
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
                    // Keeping the same username the client already has must
                    // not flag itself as "taken" — only a genuinely
                    // different, already-in-use name is invalid.
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
                        // Renaming requires a new Linux user for the new
                        // username — only proceed with the config update
                        // (and ask about the old one's content) once that
                        // actually succeeded, same "don't persist ahead of
                        // reality" rule AddClientDialog follows for a
                        // brand-new client.
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
        // Centered on *this* dialog's own window, not the main window —
        // now that dialogs are real separate windows, this reads better as
        // appearing directly over the dialog that spawned it.
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
