import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Window

// Generic, reusable themed yes/no confirmation dialog — per CLAUDE.md's
// "favor small, composable components" convention, built once here rather
// than one-off inline inside whichever dialog first needed a confirm step
// (currently: the "delete the original client's content?" prompt after a
// username change in EditClientDialog.qml).
//
// A real top-level Window, not a Popup — see AddClientDialog.qml's comment
// on why: `popupType: Popup.Window` still creates a window carrying the
// Qt::Popup flag under the hood, which window managers deliberately treat
// as unmanaged (no drag-to-move via mouse-down+Meta, the convention this
// whole app otherwise relies on for moving its own frameless main window)
// and on why `flags` below must match Main.qml's own exactly, not
// `Qt.Dialog`.
Window {
    id: root

    property var anchorWindow: null
    property string message: ""
    property string confirmLabel: "Yes"
    property string cancelLabel: "No"

    signal confirmed()
    signal cancelled()

    flags: Qt.FramelessWindowHint | Qt.Window
    modality: Qt.WindowModal
    color: "transparent"
    visible: false
    width: 360 * Theme.uiScale
    height: contentColumn.implicitHeight + dialogPadding * 2

    readonly property real dialogPadding: 24 * Theme.uiScale

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
                text: root.message
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSizeMedium
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            RowLayout {
                Layout.alignment: Qt.AlignLeft
                spacing: Theme.spacing

                ThemedButton {
                    text: root.cancelLabel
                    onClicked: {
                        root.close()
                        root.cancelled()
                    }
                }
                ThemedButton {
                    text: root.confirmLabel
                    onClicked: {
                        root.close()
                        root.confirmed()
                    }
                }
            }
        }
    }
}
