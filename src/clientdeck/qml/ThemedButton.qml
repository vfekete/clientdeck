import QtQuick
import QtQuick.Controls.Basic

// Generic, reusable themed push button, used by every dialog's
// Cancel/Add/Apply/Browse/etc. button. See docs/comments-details.md [33].
Button {
    id: root

    // Destructive action (e.g. Remove): danger-colored text and hover.
    property bool danger: false

    padding: Theme.fieldPadding
    leftPadding: Theme.fieldPadding * 1.5
    rightPadding: Theme.fieldPadding * 1.5

    contentItem: Text {
        text: root.text
        color: !root.enabled ? Theme.textSecondary : (root.danger && !root.down ? Theme.danger : Theme.textPrimary)
        font.pixelSize: Theme.fontSizeMedium
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    background: Rectangle {
        implicitHeight: Theme.smallIconButtonSize
        radius: Theme.cornerRadius / 2
        color: !root.enabled
            ? Theme.surface
            : (root.down ? (root.danger ? Theme.danger : Theme.accent)
                : (root.hovered ? (root.danger ? Theme.dangerSurface : Theme.surfaceHover) : Theme.surface))
        opacity: root.enabled ? 1.0 : 0.5
        border.width: 1
        border.color: Theme.surfaceGlass

        Behavior on color { ColorAnimation { duration: Theme.animationDuration } }
    }
}
