import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Window

// Generic, reusable themed yes/no confirmation dialog (currently used by
// the "delete the original client's content?" prompt in EditClientDialog.qml).
// Real top-level Window with flags matching Main.qml — see docs/comments-details.md [40].
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

    // x/y set once, imperatively, not as a live binding — see [41].
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
