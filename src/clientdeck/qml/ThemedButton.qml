import QtQuick
import QtQuick.Controls.Basic

// Generic, reusable themed push button — a plain QtQuick.Controls.Basic
// `Button` never adapts to Theme.isDark on its own (it has its own
// hardcoded default background/text colors, independent of this app's
// theme entirely); confirmed the hard way as the "button is dark on light
// theme" / "buttons are dark in light theme" reports across every dialog
// that used a bare `Button`. Fully owns its own background/contentItem
// (same approach as ValidatedTextField/SquareIconButton) rather than
// trying to coax the right look out of Controls Basic's palette, so every
// dialog's Cancel/Add/Apply/Browse/etc. button reuses this instead of a
// bare `Button`.
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
