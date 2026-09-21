import QtQuick
import QtQuick.Controls.Basic

// Generic, reusable themed push button, used by every dialog's
// Cancel/Add/Apply/Browse/etc. button. See docs/comments-details.md [33].
Button {
    id: root

    padding: Theme.fieldPadding
    leftPadding: Theme.fieldPadding * 1.5
    rightPadding: Theme.fieldPadding * 1.5

    contentItem: Text {
        text: root.text
        color: root.enabled ? Theme.textPrimary : Theme.textSecondary
        font.pixelSize: Theme.fontSizeMedium
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    background: Rectangle {
        implicitHeight: Theme.smallIconButtonSize
        radius: Theme.cornerRadius / 2
        color: !root.enabled
            ? Theme.surface
            : (root.down ? Theme.accent : (root.hovered ? Theme.surfaceHover : Theme.surface))
        opacity: root.enabled ? 1.0 : 0.5
        border.width: 1
        border.color: Theme.surfaceGlass

        Behavior on color { ColorAnimation { duration: Theme.animationDuration } }
    }
}
