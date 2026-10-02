import QtQuick
import QtQuick.Layouts

// Collapsible section: a clickable "▸ Title ────" header, with whatever is
// declared inside shown below it only while expanded — see
// docs/comments-details.md [128].
ColumnLayout {
    id: root

    property string title: ""
    property bool expanded: false
    // Body's left indent; default lines it up with the title text.
    property real contentIndent: Theme.fontSizeMedium + Theme.spacing / 2
    default property alias content: body.data

    spacing: Theme.spacing

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacing / 2

        Text {
            // Fixed-width glyph slot so the title doesn't shift on toggle.
            Layout.preferredWidth: Theme.fontSizeMedium
            text: root.expanded ? "▾" : "▸"
            color: headerHover.hovered ? Theme.textPrimary : Theme.textSecondary
            font.pixelSize: Theme.fontSizeMedium
        }
        Text {
            text: root.title
            color: headerHover.hovered ? Theme.textPrimary : Theme.textSecondary
            font.pixelSize: Theme.fontSizeMedium
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            implicitHeight: 1
            color: Theme.surfaceGlass
        }

        HoverHandler {
            id: headerHover
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            onTapped: root.expanded = !root.expanded
        }
    }

    ColumnLayout {
        id: body
        Layout.fillWidth: true
        Layout.leftMargin: root.contentIndent
        spacing: Theme.spacing
        visible: root.expanded
    }
}
