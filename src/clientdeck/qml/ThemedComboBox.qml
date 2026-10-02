import QtQuick
import QtQuick.Controls.Basic

// App-themed ComboBox: field-styled box (same look as ValidatedTextField),
// themed popup list. Full override for the same reason as [50].
ComboBox {
    id: control

    implicitHeight: Theme.smallIconButtonSize
    font.pixelSize: Theme.fontSizeMedium
    leftPadding: Theme.fieldPadding
    rightPadding: Theme.fieldRightPadding

    contentItem: Text {
        text: control.displayText
        color: Theme.textPrimary
        font: control.font
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    indicator: Text {
        x: control.width - width - Theme.fieldPadding
        y: (control.height - height) / 2
        text: "▾"
        color: control.hovered ? Theme.textPrimary : Theme.textSecondary
        font.pixelSize: Theme.fontSizeMedium
    }

    background: Rectangle {
        radius: Theme.cornerRadius / 2
        color: control.hovered ? Theme.surfaceHover : Theme.surfaceGlass
        border.width: control.activeFocus || control.popup.visible ? 1 : 0
        border.color: Theme.accent

        Behavior on color { ColorAnimation { duration: Theme.animationDuration } }
    }

    delegate: ItemDelegate {
        id: itemDelegate
        width: ListView.view.width
        hoverEnabled: true
        highlighted: control.highlightedIndex === index
        text: control.textRole ? modelData[control.textRole] : modelData

        background: Rectangle {
            color: itemDelegate.highlighted || itemDelegate.hovered ? Theme.surfaceHover : "transparent"
        }
        contentItem: Text {
            text: itemDelegate.text
            color: Theme.textPrimary
            font: control.font
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
        }
    }

    popup: Popup {
        y: control.height + 2
        width: control.width
        implicitHeight: Math.min(contentItem.implicitHeight + 2 * padding, 320 * Theme.uiScale)
        padding: 1

        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: control.popup.visible ? control.delegateModel : null
            currentIndex: control.highlightedIndex
            ScrollIndicator.vertical: ScrollIndicator {}
        }

        background: Rectangle {
            color: Theme.surface
            radius: Theme.cornerRadius / 2
            border.color: Theme.surfaceGlass
            border.width: 1
        }
    }
}
