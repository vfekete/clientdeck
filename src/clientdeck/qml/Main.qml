import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls.Basic

// Borderless main window. No custom titlebar/drag handling — dragging is
// via the window manager convention (mouse-down + Meta), per CLAUDE.md.
Window {
    id: window

    flags: Qt.FramelessWindowHint | Qt.Window
    // Transparent window + an inner rounded, borderless glass panel filling
    // it (below) — the four corners outside that panel stay transparent,
    // which is what makes the window itself read as a rounded shape rather
    // than a rectangle with rounded content inside a square frame.
    color: "transparent"
    x: initialX
    y: initialY
    width: initialWidth
    height: initialHeight
    visible: true
    title: "ClientDeck"

    // The window's floor size — what it actually takes to show its content
    // without clipping anything, i.e. "content boundaries": the bottom
    // toolbar's natural width AND the widest currently-rendered client
    // row's natural width (whichever is bigger), plus the same margin the
    // layout uses on every other edge (Theme.spacing * 2, matching the
    // ColumnLayout's anchors.margins below). `clientListColumn.implicitWidth`
    // (declared further down) is the real, reactive source for the
    // client-row side of this — see its own comment for why a Repeater in
    // a plain ColumnLayout is used there instead of a virtualizing
    // ListView, specifically so this number is accurate. Recomputed
    // reactively as Theme.uiScale (or the client list) changes either
    // side's natural size. Binding this to Window.minimumWidth/
    // minimumHeight does two things at once: the window manager won't let
    // the user shrink the window past it interactively, and (below) it's
    // exactly the threshold used to grow the window only when genuinely
    // needed.
    readonly property int _toolbarButtonCount: 4
    readonly property real _toolbarWidth: _toolbarButtonCount * Theme.smallIconButtonSize
        + (_toolbarButtonCount - 1) * Theme.spacing
    readonly property real _outerMargin: Theme.spacing * 2

    minimumWidth: Math.max(_toolbarWidth, clientListColumn.implicitWidth) + _outerMargin * 2
    minimumHeight: Theme.smallIconButtonSize + _outerMargin * 2 + Theme.spacing

    // Zoom (Theme.uiScale/zoomIn()/zoomOut()) never shrinks the window back
    // down on its own, but zooming in can raise the floor above the
    // window's current size — grow only exactly enough to stay at or above
    // that floor, and only when actually needed (never when the window is
    // already comfortably bigger than the toolbar requires). This also
    // makes rapid zoom in/out/in/out never compound: each check is against
    // the window's *current* size, not a remembered ratio, so a full
    // round trip back to the same scale leaves the window untouched.
    onMinimumWidthChanged: if (width < minimumWidth) width = minimumWidth
    onMinimumHeightChanged: if (height < minimumHeight) height = minimumHeight

    // Qt.ApplicationShortcut (not the default Qt.WindowShortcut): a modal
    // Popup (AddClientDialog/AddAppDialog) capturing focus otherwise
    // stopped these from firing at all while a dialog was open — the
    // default window-scoped context apparently doesn't count a focused
    // Popup's content as "the window" for shortcut-matching purposes.
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

        // Catches clicks that land on empty background (not on any
        // button) — the other half of "user clicks elsewhere" alongside
        // SquareIconButton's own onPressed, which handles a click landing
        // on a *different* button. Declared first/beneath the real content
        // below, so any actual button's own MouseArea still gets first
        // claim at its own coordinates; this only ever sees clicks at
        // points nothing else claimed.
        MouseArea {
            anchors.fill: parent
            onPressed: (mouse) => {
                DeleteArmState.disarmAny()
                mouse.accepted = false
            }
        }

        // Idle: the normal resting glass translucency. Hovered (mouse
        // anywhere over the app): fades toward opaque so content is easier
        // to read while actually using it, then back to the same resting
        // translucency the instant the mouse leaves — never fully opaque,
        // just "closer to" it, per the request. `topAlpha` carries that
        // hover behavior; `bottomAlpha` is always a fixed fraction of it
        // (Theme.glassPanelBottomRatio), so the top-vs-bottom contrast
        // holds in both resting and hovered states, and animating just
        // `topAlpha` (via Behavior) smoothly co-animates `bottomAlpha` too
        // since it's a live binding on top of it.
        property real topAlpha: panelHoverHandler.hovered ? Theme.glassPanelHoverAlpha : Theme.glassPanelAlpha
        property real bottomAlpha: topAlpha * Theme.glassPanelBottomRatio

        Behavior on topAlpha { NumberAnimation { duration: Theme.animationDuration } }

        // Linear top-to-bottom opacity fade — top more opaque than bottom,
        // per the request. Revisit (e.g. a radial fade, or non-linear
        // stops) if a straight linear slope doesn't read well.
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

                // A plain ColumnLayout + Repeater, not a virtualizing
                // ListView: only currently-instantiated delegates report a
                // usable implicitWidth, and a virtualized ListView doesn't
                // keep off-screen rows instantiated — its own implicitWidth
                // also doesn't naturally reflect delegate content at all.
                // A Layout, by contrast, always correctly and reactively
                // aggregates its children's implicit sizes (that's the
                // whole point of the Layout system), which is exactly what
                // window.minimumWidth above needs to actually respect
                // content boundaries instead of guessing. Not virtualizing
                // is fine here: this is a small personal client list, not
                // a large dynamic dataset.
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
                            tooltipText: "Add client"
                            onClicked: addClientDialog.open()
                        }
                    }
                }
            }

            // Bottom-left theme toggle + zoom in/out/reset — always present
            // regardless of empty-state vs. populated list, since it's the
            // last row. Exactly these 4 buttons is what
            // window._toolbarButtonCount above assumes for the minimum-size
            // calculation — keep them in sync if this row's button count
            // ever changes.
            RowLayout {
                Layout.alignment: Qt.AlignLeft
                spacing: Theme.spacing

                SquareIconButton {
                    implicitWidth: Theme.smallIconButtonSize
                    implicitHeight: Theme.smallIconButtonSize
                    label: Theme.isDark ? "☀" : "☾"
                    tooltipText: Theme.isDark ? "Switch to light theme" : "Switch to dark theme"
                    tooltipAbove: true
                    // Switching theme is an incidental display preference,
                    // not an action on any app — it shouldn't cancel a
                    // pending delete confirmation on some other button.
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
                    // Resets the *scale* only — window size is never
                    // forced to a fixed value here, for the same reason
                    // zoom itself never shrinks the window: this just
                    // becomes a scale change like any other, so it goes
                    // through the exact same onMinimumWidthChanged/
                    // onMinimumHeightChanged grow-only-if-needed logic
                    // above instead of overriding whatever size the user
                    // (or a previous session) already had the window at.
                    onClicked: Theme.resetZoom()
                }
            }
        }
    }

    AddClientDialog {
        id: addClientDialog
        anchorItem: window.contentItem
    }

    AddAppDialog {
        id: addAppDialog
        anchorItem: window.contentItem
    }

    EditClientDialog {
        id: editClientDialog
        anchorItem: window.contentItem
    }
}
