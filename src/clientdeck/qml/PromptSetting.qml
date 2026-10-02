import QtQuick
import QtQuick.Layouts

// "Set bash prompt (PS1)" option for a client dialog's Advanced section:
// checkbox + "Configure" button (opens Ps1ConfigDialog), with the chosen
// prompt's name underneath. See docs/comments-details.md [135].
ColumnLayout {
    id: root

    property alias enabledSetting: setPromptCheck.checked
    property string ps1: ps1Renderer.defaultPs1()
    property string username: ""
    // Window the configure dialog centers over (the owning client dialog).
    property var anchorWindow: null
    // Preset name matching `ps1`, or "Custom".
    readonly property string promptName: {
        const match = ps1Renderer.presets().find(p => p.ps1 === root.ps1)
        return match ? match.name : "Custom"
    }

    function reset() {
        setPromptCheck.checked = false
        root.ps1 = ps1Renderer.defaultPs1()
    }

    spacing: 0

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacing

        ThemedCheckBox {
            id: setPromptCheck
            text: "Set bash prompt (PS1)"
        }
        Item { Layout.fillWidth: true }
        ThemedButton {
            text: "Configure"
            enabled: setPromptCheck.checked
            onClicked: configDialog.openWith(root.ps1, root.username)
        }
    }

    // Lines up with the checkbox's label text.
    Text {
        Layout.leftMargin: setPromptCheck.indicator.width + setPromptCheck.spacing
        text: "Selected: " + root.promptName
        color: Theme.textSecondary
        opacity: setPromptCheck.checked ? 1.0 : 0.5
        font.pixelSize: Theme.fontSizeBody
    }

    Ps1ConfigDialog {
        id: configDialog
        anchorWindow: root.anchorWindow
        onApplied: (value) => root.ps1 = value
    }
}
