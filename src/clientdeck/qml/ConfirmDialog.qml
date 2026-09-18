import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// Generic, reusable themed yes/no confirmation dialog — per CLAUDE.md's
// "favor small, composable components" convention, built once here rather
// than one-off inline inside whichever dialog first needed a confirm step
// (currently: the "delete the original client's content?" prompt after a
// username change in EditClientDialog.qml).
Popup {
    id: root

    property var anchorItem: null
    property string message: ""
    property string confirmLabel: "Yes"
    property string cancelLabel: "No"

    signal confirmed()
    signal cancelled()

    modal: true
    focus: true
    width: 360 * Theme.uiScale
    padding: 24 * Theme.uiScale
    x: anchorItem ? (anchorItem.width - width) / 2 : 0
    y: anchorItem ? (anchorItem.height - height) / 2 : 0

    background: Rectangle {
        color: Theme.surface
        radius: Theme.cornerRadius
        border.color: Theme.surfaceGlass
        border.width: 1
    }

    ColumnLayout {
        width: parent.width
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

            Button {
                text: root.cancelLabel
                onClicked: {
                    root.close()
                    root.cancelled()
                }
            }
            Button {
                text: root.confirmLabel
                onClicked: {
                    root.close()
                    root.confirmed()
                }
            }
        }
    }
}
