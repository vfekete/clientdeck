import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// Generic, reusable themed tooltip. See docs/comments-details.md [34].
Popup {
    id: root

    property alias title: titleText.text
    property alias description: descriptionText.text

    // Purely hover-driven, not a normal interactive Popup — see [35].
    focus: false
    modal: false
    closePolicy: Popup.NoAutoClose
    padding: Theme.fieldPadding

    background: Rectangle {
        color: Theme.glassPanel
        radius: Theme.cornerRadius / 2
        border.width: 0
    }

    contentItem: ColumnLayout {
        spacing: 2

        Text {
            id: titleText
            color: Theme.textPrimary
            font.pixelSize: Theme.fontSizeBody
            font.bold: true
        }

        Text {
            id: descriptionText
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSizeSmall
            visible: text.length > 0
            wrapMode: Text.WordWrap
            Layout.maximumWidth: 240 * Theme.uiScale
        }
    }
}
