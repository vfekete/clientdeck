import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Window

// Themed "configure bash prompt" dialog: preset picker, PS1 input with
// colon hints, live two-terminal preview, Reset / Cancel / Apply.
// Real top-level Window with flags matching Main.qml — see docs/comments-details.md [40].
Window {
    id: root

    property var anchorWindow: null
    property string username: ""
    readonly property var presets: ps1Renderer.presets()
    // Preset the current text is based on; -1 = custom (matches none).
    property int basePresetIndex: -1
    property int pendingPresetIndex: -1
    readonly property bool modified: basePresetIndex < 0
        || ps1Field.text !== presets[basePresetIndex].ps1

    signal applied(string value)

    // Same label-column layout as EditClientDialog — see [44].
    readonly property real fieldLabelWidth: 70 * Theme.uiScale
    readonly property real dialogPadding: 24 * Theme.uiScale

    flags: Qt.FramelessWindowHint | Qt.Window
    modality: Qt.WindowModal
    color: "transparent"
    visible: false
    width: 560 * Theme.uiScale
    height: contentColumn.implicitHeight + dialogPadding * 2

    // x/y set once, imperatively, not as a live binding — see [41].
    function open() {
        if (anchorWindow) {
            root.x = anchorWindow.x + (anchorWindow.width - root.width) / 2
            root.y = anchorWindow.y + (anchorWindow.height - root.height) / 2
        }
        root.visible = true
        // Explicit activation request — see [123].
        root.requestActivate()
    }
    function close() {
        root.visible = false
        // Hand focus back to the dialog underneath — see [137].
        if (anchorWindow)
            anchorWindow.requestActivate()
    }

    function openWith(ps1, username) {
        root.username = username
        ps1Field.text = ps1
        root.basePresetIndex = root.presets.findIndex(p => p.ps1 === ps1)
        presetCombo.currentIndex = root.basePresetIndex
        root.open()
        ps1Field.forceActiveFocus()
    }

    function applyPreset(index) {
        root.basePresetIndex = index
        presetCombo.currentIndex = index
        ps1Field.text = root.presets[index].ps1
    }

    // Warns before replacing edited text with a preset — see [133].
    function requestPreset(index) {
        if (index === root.basePresetIndex && !root.modified)
            return
        if (root.modified) {
            root.pendingPresetIndex = index
            presetCombo.currentIndex = root.basePresetIndex
            discardChangesConfirm.open()
            return
        }
        root.applyPreset(index)
    }

    // Only while this window is focused — nested dialogs' Escape shortcuts
    // would otherwise all match at once and cancel out; see [137].
    Shortcut {
        sequence: "Escape"
        enabled: focusTracker.focusWindow === root
        onActivated: root.close()
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.surface
        radius: Theme.cornerRadius
        border.color: Theme.surfaceGlass
        border.width: 1

        ColumnLayout {
            id: contentColumn
            anchors.fill: parent
            anchors.margins: root.dialogPadding
            spacing: Theme.spacing

            Text {
                text: "Bash prompt"
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSizeLarge
                font.bold: true
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing

                Text {
                    text: "Preset"
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeBody
                    Layout.preferredWidth: root.fieldLabelWidth
                }
                ThemedComboBox {
                    id: presetCombo
                    Layout.fillWidth: true
                    model: root.presets
                    textRole: "name"
                    displayText: root.basePresetIndex < 0
                        ? "Custom"
                        : root.presets[root.basePresetIndex].name + (root.modified ? " (modified)" : "")
                    onActivated: (index) => root.requestPreset(index)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing

                Text {
                    text: "PS1"
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeBody
                    Layout.preferredWidth: root.fieldLabelWidth
                }
                // Type ":" for hints (:user, :hostname, …) — see [136].
                ColonHintTextField {
                    id: ps1Field
                    Layout.fillWidth: true
                    font.family: Theme.monoFontFamily
                    font.pixelSize: Theme.fontSizeBody
                    placeholderText: "PS1"
                    hints: ps1Renderer.hints()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing

                Text {
                    text: "Preview"
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeBody
                    Layout.preferredWidth: root.fieldLabelWidth
                    Layout.alignment: Qt.AlignTop
                    topPadding: Theme.fieldPadding / 2
                }
                Ps1Preview {
                    Layout.fillWidth: true
                    ps1: ps1Field.text
                    username: root.username
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacing / 2
                spacing: Theme.spacing

                ThemedButton {
                    text: "Reset"
                    onClicked: root.applyPreset(0)
                }
                Item { Layout.fillWidth: true }
                ThemedButton {
                    text: "Cancel"
                    onClicked: root.close()
                }
                ThemedButton {
                    text: "Apply"
                    onClicked: {
                        root.applied(ps1Field.text)
                        root.close()
                    }
                }
            }
        }
    }

    ConfirmDialog {
        id: discardChangesConfirm
        // Anchored to this dialog, not the main window — see [48].
        anchorWindow: root
        message: "The PS1 has been changed. Switching to the \""
            + (root.pendingPresetIndex >= 0 ? root.presets[root.pendingPresetIndex].name : "")
            + "\" preset will replace your changes. Continue?"
        confirmLabel: "Yes"
        cancelLabel: "No"
        onConfirmed: root.applyPreset(root.pendingPresetIndex)
    }
}
