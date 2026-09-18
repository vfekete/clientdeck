import QtQuick
import QtQuick.Controls.Basic

// Generic, reusable themed search field: a magnifying-glass icon + hint
// text, both shown only while the field is unfocused AND empty.
//
// Named ThemedSearchField, not SearchField: Qt 6.7+'s QtQuick.Controls
// styles (Basic included) already ship their own built-in `SearchField`
// type, and since callers of this component explicitly `import
// QtQuick.Controls.Basic`, that explicit import wins any name collision
// against this file's implicit same-directory availability — using the
// same name silently resolved to Qt's own SearchField instead of this
// one, which only surfaced as "Cannot assign to non-existent property
// hintText" (confirmed by loading this file in isolation, where it
// worked fine, versus by name from another file in the same directory,
// where it didn't).
//
// Deliberately not the standard `placeholderText` behavior (which stays
// visible whenever the field is empty, focused or not) — here the icon
// and hint disappear the moment the field gains focus, even if nothing's
// been typed yet, and only reappear once focus is lost and it's still
// empty. Built once here rather than special-cased in the "add app"
// dialog's search box, so any other search/filter field can reuse it.
TextField {
    id: root

    property string hintText: "Search"

    // Reserve room for the icon+hint at the left, in every state, so
    // typed text lines up in the same place whether the hint is showing
    // or not (rather than text jumping left the instant it disappears).
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
