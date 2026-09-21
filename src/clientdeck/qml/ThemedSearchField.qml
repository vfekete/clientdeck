import QtQuick
import QtQuick.Controls.Basic

// Generic, reusable themed search field: a magnifying-glass icon + hint
// text, shown only while unfocused AND empty.
// Named ThemedSearchField, not SearchField — see docs/comments-details.md [37].
// Icon/hint visibility is deliberately not just placeholderText — see [38].
TextField {
    id: root

    property string hintText: "Search"

    // Always-reserved left padding, so text doesn't jump — see [39].
    readonly property real _iconReserve: Theme.fontSizeMedium + Theme.spacing / 2

    color: Theme.textPrimary
    selectByMouse: true
    font.pixelSize: Theme.fontSizeMedium
    topPadding: Theme.fieldPadding
    bottomPadding: Theme.fieldPadding
    rightPadding: Theme.fieldPadding
    leftPadding: Theme.fieldPadding + _iconReserve

    background: Rectangle {
        radius: Theme.cornerRadius / 2
        color: Theme.surfaceGlass
        border.width: root.activeFocus ? 1 : 0
        border.color: Theme.accent

        Behavior on border.color { ColorAnimation { duration: Theme.animationDuration } }
    }

    Row {
        anchors.left: parent.left
        anchors.leftMargin: Theme.fieldPadding
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacing / 2
        visible: !root.activeFocus && root.text.length === 0

        Text {
            text: "🔍"
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSizeMedium
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            text: root.hintText
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSizeMedium
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
