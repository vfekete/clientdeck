import QtQuick
import QtQuick.Controls.Basic

// ValidatedTextField with "colon hints": typing ":" opens a small list of
// `hints` ({keyword, value, description}), filtered by prefix as the user
// keeps typing; choosing one replaces ":keyword…" with its value, Escape
// keeps the typed text literally. See docs/comments-details.md [136].
ValidatedTextField {
    id: root

    property var hints: []
    // Position of the ":" that opened the list; -1 = not completing.
    property int hintAnchor: -1
    readonly property bool hintsOpen: hintPopup.visible
    property var filteredHints: []
    // Set by the ":" key press, consumed by the edit it produces.
    property bool colonTyped: false

    function closeHints() {
        root.hintAnchor = -1
        hintPopup.close()
    }

    // Text typed after the ":" so far, or null if completion should stop.
    function currentQuery() {
        if (root.hintAnchor < 0 || root.cursorPosition <= root.hintAnchor
                || root.text.charAt(root.hintAnchor) !== ":")
            return null
        const query = root.text.slice(root.hintAnchor + 1, root.cursorPosition)
        return /^[A-Za-z0-9]*$/.test(query) ? query.toLowerCase() : null
    }

    function refreshHints() {
        const query = root.currentQuery()
        if (query === null) {
            root.closeHints()
            return
        }
        root.filteredHints = root.hints.filter(h => h.keyword.startsWith(query))
        if (root.filteredHints.length === 0) {
            root.closeHints()
            return
        }
        hintList.currentIndex = 0
        hintPopup.open()
    }

    function acceptHint(index) {
        const hint = root.filteredHints[index]
        const start = root.hintAnchor
        const end = root.cursorPosition
        root.closeHints()
        root.remove(start, end)
        root.insert(start, hint.value)
        root.cursorPosition = start + hint.value.length
        root.forceActiveFocus()
    }

    onTextEdited: {
        if (root.colonTyped && root.hintAnchor < 0 && root.text.charAt(root.cursorPosition - 1) === ":")
            root.hintAnchor = root.cursorPosition - 1
        root.colonTyped = false
        if (root.hintAnchor >= 0)
            root.refreshHints()
    }
    onCursorPositionChanged: if (root.hintAnchor >= 0 && root.currentQuery() === null) root.closeHints()
    onActiveFocusChanged: if (!root.activeFocus && !hintPopup.hovered) root.closeHints()

    // Claims Escape while the list is open, so it reaches onPressed below
    // instead of firing a window-level Escape shortcut (e.g. close dialog).
    Keys.onShortcutOverride: (event) => event.accepted = hintPopup.visible && event.key === Qt.Key_Escape
    Keys.onPressed: (event) => {
        if (event.text === ":" && !hintPopup.visible)
            root.colonTyped = true
        if (!hintPopup.visible)
            return
        if (event.key === Qt.Key_Escape) {
            root.closeHints()
            event.accepted = true
        } else if (event.key === Qt.Key_Down) {
            hintList.currentIndex = (hintList.currentIndex + 1) % hintList.count
            event.accepted = true
        } else if (event.key === Qt.Key_Up) {
            hintList.currentIndex = (hintList.currentIndex - 1 + hintList.count) % hintList.count
            event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Tab) {
            root.acceptHint(hintList.currentIndex)
            event.accepted = true
        }
    }

    Popup {
        id: hintPopup

        readonly property real rowHeight: Theme.fontSizeBody + Theme.fieldPadding

        // Under the ":" that opened it, clamped to the field's width.
        x: Math.max(0, Math.min(
            root.hintAnchor >= 0 ? root.positionToRectangle(root.hintAnchor).x : 0,
            root.width - width))
        y: root.height + 2
        width: Math.min(root.width, 360 * Theme.uiScale)
        height: Math.min(hintList.count, 6) * rowHeight + 2 * padding
        padding: 1
        // Never steals focus from the field; closed only by the field.
        focus: false
        closePolicy: Popup.NoAutoClose

        background: Rectangle {
            color: Theme.surface
            radius: Theme.cornerRadius / 2
            border.color: Theme.surfaceGlass
            border.width: 1
        }

        contentItem: ListView {
            id: hintList
            clip: true
            model: root.filteredHints
            boundsBehavior: Flickable.StopAtBounds
            ScrollIndicator.vertical: ScrollIndicator {}

            delegate: Rectangle {
                id: hintRow

                required property var modelData
                required property int index

                width: ListView.view.width
                height: hintPopup.rowHeight
                radius: Theme.cornerRadius / 4
                color: hintList.currentIndex === index || rowHover.hovered ? Theme.surfaceHover : "transparent"

                Row {
                    id: hintCodes
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.fieldPadding
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacing

                    Text {
                        text: ":" + hintRow.modelData.keyword
                        color: Theme.textPrimary
                        font.family: Theme.monoFontFamily
                        font.pixelSize: Theme.fontSizeBody
                    }
                    Text {
                        text: hintRow.modelData.value
                        color: Theme.accent
                        font.family: Theme.monoFontFamily
                        font.pixelSize: Theme.fontSizeBody
                    }
                }
                Text {
                    anchors.left: hintCodes.right
                    anchors.right: parent.right
                    anchors.leftMargin: Theme.spacing
                    anchors.rightMargin: Theme.fieldPadding
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideRight
                    text: hintRow.modelData.description
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeSmall
                }

                HoverHandler { id: rowHover }
                TapHandler { onTapped: root.acceptHint(hintRow.index) }
            }
        }
    }
}
