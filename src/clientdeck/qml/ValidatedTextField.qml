import QtQuick
import QtQuick.Controls.Basic

// Generic, reusable live-validated input with themed error state.
// See docs/comments-details.md [36].
TextField {
    id: root

    // JS function: (text) -> bool. true = valid. null = always valid.
    property var validator: null
    property bool touched: false
    readonly property bool isValid: !touched || validator === null || validator(text)
    property string errorText: "That value isn't valid."

    color: Theme.textPrimary
    placeholderTextColor: Theme.textSecondary
    selectByMouse: true
    font.pixelSize: Theme.fontSizeMedium
    padding: Theme.fieldPadding
    rightPadding: Theme.fieldRightPadding

    onTextChanged: touched = true

    background: Rectangle {
        radius: Theme.cornerRadius / 2
        color: root.isValid ? Theme.surfaceGlass : Theme.dangerSurface
        border.width: root.isValid ? (root.activeFocus ? 1 : 0) : 1
        border.color: root.isValid ? Theme.accent : Theme.danger

        Behavior on color { ColorAnimation { duration: Theme.animationDuration } }
        Behavior on border.color { ColorAnimation { duration: Theme.animationDuration } }
    }

    Text {
        text: "⚠"
        color: Theme.danger
        visible: !root.isValid
        font.pixelSize: Theme.fontSizeMedium
        anchors.right: parent.right
        anchors.rightMargin: Theme.fieldPadding
        anchors.verticalCenter: parent.verticalCenter
    }

    Text {
        anchors.top: root.bottom
        anchors.left: root.left
        anchors.topMargin: 4
        visible: !root.isValid
        text: root.errorText
        color: Theme.danger
        font.pixelSize: Theme.fontSizeSmall
    }
}
