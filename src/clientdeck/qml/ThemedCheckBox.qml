import QtQuick
import QtQuick.Controls.Basic

// App-themed CheckBox (accent-filled box + check glyph, themed label).
// Custom contentItem for the same reason as AddAppDialog's ItemDelegate —
// see docs/comments-details.md [50].
CheckBox {
    id: control

    // Box flush with the left edge of surrounding fields/labels.
    leftPadding: 0

    contentItem: Text {
        text: control.text
        color: Theme.textPrimary
        font.pixelSize: Theme.fontSizeMedium
        verticalAlignment: Text.AlignVCenter
        leftPadding: control.indicator.width + control.spacing
    }

    indicator: Rectangle {
        implicitWidth: Theme.fontSizeLarge
        implicitHeight: Theme.fontSizeLarge
        x: control.leftPadding
        y: parent.height / 2 - height / 2
        radius: Theme.cornerRadius / 4
        color: control.checked ? Theme.accent : Theme.surfaceGlass
        border.width: 1
        border.color: Theme.accent

        Text {
            anchors.centerIn: parent
            text: "✓"
            color: Theme.textPrimary
            visible: control.checked
            font.pixelSize: Theme.fontSizeSmall
        }
    }
}
