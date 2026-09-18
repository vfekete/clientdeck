import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// Generic, reusable themed tooltip — a small glass panel showing a title
// and optional description, meant to replace the default OS/Basic-style
// tooltip anywhere hover info is needed (not just the client logo), per
// CLAUDE.md's "consistent dark theme" requirement.
Popup {
    id: root

    property alias title: titleText.text
    property alias description: descriptionText.text

    // Positioned by the caller (via `parent` + x/y), shown/hidden purely
    // by binding `visible` to a HoverHandler — never grabs focus or
    // participates in click-to-dismiss like a real Popup normally would.
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
