import QtQuick
import QtQuick.Layouts

// Two miniature terminal windows — dark and light, regardless of the app
// theme — each with a title bar (the title the PS1 itself sets) and a
// short session rendered with the PS1's ANSI colors. See
// docs/comments-details.md [130], [134].
ColumnLayout {
    id: root

    property string ps1: ""
    property string username: ""

    spacing: Theme.spacing

    Repeater {
        model: [true, false]  // dark terminal, light terminal

        delegate: Rectangle {
            id: terminal

            required property bool modelData
            readonly property var colors: ps1Renderer.terminalColors(modelData)
            readonly property real titleBarHeight: Theme.fontSizeSmall + Theme.fieldPadding

            Layout.fillWidth: true
            implicitHeight: titleBarHeight + sessionText.implicitHeight + Theme.fieldPadding * 1.5
            radius: Theme.cornerRadius / 2
            color: colors.background
            border.width: 1
            border.color: colors.border

            // Title bar: rounded top corners only (square filler below).
            Rectangle {
                id: titleBar
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 1
                height: terminal.titleBarHeight
                radius: terminal.radius - 1
                color: terminal.colors.titleBar

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: parent.radius
                    color: parent.color
                }

                Text {
                    anchors.centerIn: parent
                    width: parent.width - windowButtons.width * 2 - Theme.fieldPadding * 2
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideMiddle
                    text: ps1Renderer.title(root.ps1, root.username)
                    color: terminal.colors.titleText
                    font.pixelSize: Theme.fontSizeSmall
                    font.bold: true
                }

                // Decorative GNOME-style window buttons.
                Row {
                    id: windowButtons
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.fieldPadding * 0.75
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.fieldPadding * 0.6

                    Repeater {
                        model: 3
                        delegate: Rectangle {
                            width: Theme.fontSizeSmall * 0.75
                            height: width
                            radius: width / 2
                            color: terminal.colors.titleText
                            opacity: 0.25
                        }
                    }
                }
            }

            Text {
                id: sessionText
                anchors.top: titleBar.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: Theme.fieldPadding * 0.5
                anchors.leftMargin: Theme.fieldPadding
                anchors.rightMargin: Theme.fieldPadding
                textFormat: Text.RichText
                // Wraps like a real terminal would, rather than clipping.
                wrapMode: Text.WrapAnywhere
                font.family: Theme.monoFontFamily
                font.pixelSize: Theme.fontSizeBody
                text: ps1Renderer.renderSession(root.ps1, root.username, terminal.modelData)
            }
        }
    }
}
