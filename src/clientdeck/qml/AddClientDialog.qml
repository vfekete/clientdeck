import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Dialogs
import QtQuick.Window

// Themed "add customer" dialog: logo, name, description, username-to-create
// (live-validated against the system's existing users/groups).
//
// A real top-level Window, not a Popup: `popupType: Popup.Window` (tried
// first) still creates a window carrying the Qt::Popup window flag under
// the hood, which window managers deliberately exempt from normal window
// management — no drag-to-move via the mouse-down+Meta convention this
// whole app otherwise relies on for its own frameless main window
// (confirmed the hard way — it did create a genuinely separate QWindow,
// just not a *movable* one).
//
// `flags` below must match Main.qml's own window flags exactly
// (`Qt.FramelessWindowHint | Qt.Window`) — an earlier attempt used
// `Qt.Dialog | Qt.FramelessWindowHint` instead, which still wasn't
// independently movable: `Qt.Dialog` carries WM-specific semantics (many
// window managers, including Mutter, can bundle a transient
// `Qt::Dialog`-flagged window with its `transientParent` for move
// operations, moving the parent instead of — or together with — the
// dialog). Using the exact same base window type as the main window,
// which is already confirmed movable, sidesteps that distinction rather
// than guessing at which WM-specific quirk it triggers.
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

    // x/y are set once here, imperatively, rather than as a live binding
    // on anchorWindow/width/height — a binding kept recentering the
    // dialog on the main window every time uiScale changed while it was
    // open (width/height are themselves uiScale-derived, so zooming
    // re-evaluated the centering expression too), overriding wherever the
    // user had actually dragged the dialog to. Size still legitimately
    // follows zoom via the width/height bindings above; position, once
    // set, is left alone until the dialog is reopened.
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
                // Theme.smallIconButtonSize * 2, not browseButton.height *
                // 2: a Layout.preferredHeight binding that reads a
                // *sibling's* live .height (itself Layout-computed) turned
                // out to be unreliable on the very first layout pass —
                // confirmed via headless testing, where this row measured
                // correctly (twice the button's height) in isolation but
                // silently came out equal to the button's own height
                // whenever the main window had other content (a client
                // row) competing for the same initial layout pass. Basing
                // it on the same Theme token ThemedButton's own height
                // already derives from sidesteps that class of timing
                // issue entirely — no runtime geometry read involved.
                //
                // Also set as `minimumHeight`, not just `preferredHeight`:
                // even with the above fix, this row's rendered height still
                // came out equal to just the button's height (not double)
                // specifically when the dialog was opened via a simulated
                // click through SquareIconButton's full press/release
                // gesture chain in headless (`QT_QPA_PLATFORM=offscreen`)
                // testing — traced as far as the *window's own contentItem*
                // reporting a stale 0×0 size in that exact scenario despite
                // `Window.height` itself already holding the correct value,
                // i.e. a window/scene-graph geometry sync gap below the
                // QML layer, not something fixable from here by changing
                // what any single binding reads (anchor restructuring, an
                // explicit `Binding`, and `Qt.callLater`-deferred rebinds
                // were all tried and made no difference). Opening the same
                // dialog via a direct `.open()` call or via
                // EditClientDialog's TapHandler-driven path both measured
                // correctly, so this may well be specific to the offscreen
                // QPA platform's handling of that exact event-delivery
                // path rather than a real on-screen bug — flagging for
                // on-host visual confirmation rather than claiming
                // certainty either way. `preferredHeight` is a hint the
                // layout can shrink below when it believes space is
                // insufficient; `minimumHeight` is a floor it cannot
                // violate regardless, which is a reasonable, low-cost
                // safeguard against this class of issue even though its
                // root cause isn't fully pinned down.
                Layout.preferredHeight: Theme.smallIconButtonSize * 2
                Layout.minimumHeight: Theme.smallIconButtonSize * 2
                spacing: Theme.spacing

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
                    onClicked: {
                        // Creating the Linux user requires root (pkexec) —
                        // only persist the client once that actually
                        // succeeded, so config never references a user
                        // that doesn't exist.
                        root.creationFailed = false
                        if (clientProvisioner.createLinuxUser(usernameField.text)) {
                            clientModel.addClient(nameField.text, descriptionField.text, usernameField.text, root.logoPath)
                            root.close()
                        } else {
                            root.creationFailed = true
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
}
