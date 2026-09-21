import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls.Basic

// Borderless main window. No custom titlebar/drag handling — dragging is
// via the window manager convention (mouse-down + Meta), per CLAUDE.md.
Window {
    id: window

    flags: Qt.FramelessWindowHint | Qt.Window
    // Transparent window + inner rounded panel = rounded window — see docs/comments-details.md [63].
    color: "transparent"
    x: initialX
    y: initialY
    width: initialWidth
    height: initialHeight
    visible: true
    title: "ClientDeck"

    // Window's floor size (content boundaries) — see [64].
    readonly property int _toolbarButtonCount: 4
    readonly property real _toolbarWidth: _toolbarButtonCount * Theme.smallIconButtonSize
        + (_toolbarButtonCount - 1) * Theme.spacing
    readonly property real _outerMargin: Theme.spacing * 2

    minimumWidth: Math.max(_toolbarWidth, clientListColumn.implicitWidth) + _outerMargin * 2
    minimumHeight: Theme.smallIconButtonSize + _outerMargin * 2 + Theme.spacing

    // Grows to the new floor, never shrinks below current size — see [65].
    onMinimumWidthChanged: if (width < minimumWidth) width = minimumWidth
    onMinimumHeightChanged: if (height < minimumHeight) height = minimumHeight

    // Qt.ApplicationShortcut, not the default — see [66].
    Shortcut {
        sequences: [StandardKey.ZoomIn]
        context: Qt.ApplicationShortcut
        onActivated: Theme.zoomIn()
    }
    Shortcut {
        sequences: [StandardKey.ZoomOut]
        context: Qt.ApplicationShortcut
        onActivated: Theme.zoomOut()
    }
    // Cancels whichever app button is currently armed for delete (showing
    // its trash-bin icon), per "user presses ESC (and application has
    // focus)".
    Shortcut {
        sequence: "Escape"
        context: Qt.ApplicationShortcut
        onActivated: DeleteArmState.disarmAny()
    }

    Rectangle {
        id: glassPanel
        anchors.fill: parent
        radius: Theme.cornerRadius * 1.5
        border.width: 0

        // Catches clicks on empty background — see [67].
        MouseArea {
            anchors.fill: parent
            onPressed: (mouse) => {
                DeleteArmState.disarmAny()
                mouse.accepted = false
            }
        }

        // Fades toward opaque on hover, never fully opaque — see [68].
        property real topAlpha: panelHoverHandler.hovered ? Theme.glassPanelHoverAlpha : Theme.glassPanelAlpha
        property real bottomAlpha: topAlpha * Theme.glassPanelBottomRatio

        Behavior on topAlpha { NumberAnimation { duration: Theme.animationDuration } }

        // Linear top-to-bottom opacity fade — see [69].
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop {
                position: 0.0
                color: Qt.rgba(Theme.glassPanelBase.r, Theme.glassPanelBase.g, Theme.glassPanelBase.b, glassPanel.topAlpha)
            }
            GradientStop {
                position: 1.0
                color: Qt.rgba(Theme.glassPanelBase.r, Theme.glassPanelBase.g, Theme.glassPanelBase.b, glassPanel.bottomAlpha)
            }
        }

        HoverHandler {
            id: panelHoverHandler
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.spacing * 2
            spacing: Theme.spacing

            // Empty state: first run, no clients configured yet.
            Item {
                visible: clientModel.count === 0
                Layout.fillWidth: true
                Layout.fillHeight: true

                SquareIconButton {
                    anchors.centerIn: parent
                    implicitWidth: Theme.hugeIconButtonSize
                    implicitHeight: Theme.hugeIconButtonSize
                    label: "+"
                    bigLabel: true
                    tooltipText: "Add client"
                    onClicked: addClientDialog.open()
                }
            }

            ScrollView {
                id: clientScrollView
                visible: clientModel.count > 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                // Plain ColumnLayout + Repeater, not a virtualizing ListView — see [70].
                ColumnLayout {
                    id: clientListColumn
                    width: clientScrollView.availableWidth
                    spacing: Theme.spacing

                    Repeater {
                        model: clientModel
                        delegate: ClientRow {
                            Layout.fillWidth: true
                            clientName: model.name
                            description: model.description
                            username: model.username
                            logoPath: model.logoPath || ""
                            apps: model.apps

                            onLaunchApp: (appIndex) => appLauncher.launchApp(username, appIndex)
                            onRemoveAppRequested: (appIndex) => clientModel.removeAppFromClient(username, appIndex)
                            onMoveAppRequested: (fromIndex, toIndex) => clientModel.moveApp(username, fromIndex, toIndex)
                            onAddAppRequested: {
                                addAppDialog.targetUsername = username
                                addAppDialog.open()
                            }
                            onEditRequested: editClientDialog.openFor(username, clientName, description, logoPath)
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Theme.rowHeight

                        SquareIconButton {
                            anchors.verticalCenter: parent.verticalCenter
                            label: "+"
                            bigLabel: true
                            tooltipText: "Add client"
                            onClicked: addClientDialog.open()
                        }
                    }
                }
            }

            // Bottom-left theme toggle + zoom in/out/reset — see [71].
            RowLayout {
                Layout.alignment: Qt.AlignLeft
                spacing: Theme.spacing

                SquareIconButton {
                    implicitWidth: Theme.smallIconButtonSize
                    implicitHeight: Theme.smallIconButtonSize
                    label: Theme.isDark ? "☀" : "☾"
                    tooltipText: Theme.isDark ? "Switch to light theme" : "Switch to dark theme"
                    tooltipAbove: true
                    // Theme switch is incidental, shouldn't cancel a pending delete.
                    cancelsOtherArmedButton: false
                    onClicked: Theme.isDark = !Theme.isDark
                }
                SquareIconButton {
                    implicitWidth: Theme.smallIconButtonSize
                    implicitHeight: Theme.smallIconButtonSize
                    label: "+"
                    enabled: Theme.uiScale < Theme.maxUiScale
                    tooltipText: "Zoom in"
                    tooltipAbove: true
                    onClicked: Theme.zoomIn()
                }
                SquareIconButton {
                    implicitWidth: Theme.smallIconButtonSize
                    implicitHeight: Theme.smallIconButtonSize
                    label: "-"
                    enabled: Theme.uiScale > Theme.minUiScale
                    tooltipText: "Zoom out"
                    tooltipAbove: true
                    onClicked: Theme.zoomOut()
                }
                SquareIconButton {
                    implicitWidth: Theme.smallIconButtonSize
                    implicitHeight: Theme.smallIconButtonSize
                    label: "↺"
                    enabled: Theme.uiScale !== 1.0
                    tooltipText: "Reset zoom"
                    tooltipAbove: true
                    // Resets scale only, not window size — see [72].
                    onClicked: Theme.resetZoom()
                }
            }
        }
    }

    AddClientDialog {
        id: addClientDialog
        anchorWindow: window
    }

    AddAppDialog {
        id: addAppDialog
        anchorWindow: window
    }

    EditClientDialog {
        id: editClientDialog
        anchorWindow: window
    }
}
