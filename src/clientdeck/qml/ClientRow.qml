import QtQuick
import QtQuick.Layouts

// One row of the main grid: client logo, then one square button per app the
// client has (every app comes from the "add app" dialog — there are no
// hardcoded/builtin apps), then a trailing "+" to register another.
RowLayout {
    id: root

    property string clientName: ""
    property string description: ""
    property string username: ""
    property string logoPath: ""
    property var apps: []

    signal launchApp(int appIndex)
    signal removeAppRequested(int appIndex)
    signal moveAppRequested(int fromIndex, int toIndex)
    signal addAppRequested()
    signal editRequested()

    spacing: Theme.spacing
    height: Theme.rowHeight

    Image {
        id: logoImage
        Layout.preferredWidth: Theme.logoSize
        Layout.preferredHeight: Theme.logoSize
        source: root.logoPath
        fillMode: Image.PreserveAspectFit

        HoverHandler {
            id: logoHoverHandler
        }

        // Double-clicking the logo opens the "modify client" dialog — see
        // CLAUDE.md's "Modifying a client" section. TapHandler (not a
        // MouseArea) since the logo needs no other pointer behavior and a
        // passive handler coexists cleanly with the HoverHandler above,
        // same reasoning as SquareIconButton's own tooltip HoverHandler.
        TapHandler {
            onDoubleTapped: root.editRequested()
        }

        ThemedTooltip {
            parent: logoImage
            x: 0
            y: logoImage.height + Theme.spacing / 2
            visible: logoHoverHandler.hovered
            title: root.clientName
            description: root.description
        }
    }

    // A plain Item + Repeater, not a Row: reordering needs each button's
    // on-screen slot to sometimes differ from its actual data index (while
    // a drag is in progress), which means computing `x` by hand per
    // delegate — a positioner like Row always overrides that itself.
    Item {
        id: appsContainer

        // RowLayout still reserves spacing on *both* sides of a child even
        // when its implicitWidth is 0 — so with zero apps, the "+" button
        // ended up one full Theme.spacing further right than a row's first
        // app button sits when apps do exist (confirmed visually: the "+"
        // in an empty row was misaligned with the first app button of a
        // populated row). Hiding this Item entirely when there's nothing
        // to show removes it from the layout altogether, matching
        // RowLayout's documented behavior for invisible children.
        visible: root.apps.length > 0

        readonly property real buttonAdvance: Theme.iconButtonSize + Theme.spacing
        // Reported to the outer RowLayout so it can size this child
        // correctly — a plain Item, unlike Row/Layout types, does not
        // compute this from its children on its own.
        implicitWidth: root.apps.length > 0 ? root.apps.length * buttonAdvance - Theme.spacing : 0
        implicitHeight: Theme.iconButtonSize

        // -1 = no drag in progress. While dragging, `draggedIndex` is the
        // app's real (data) index and `dropIndex` is the slot the drag is
        // currently hovering over — which becomes the new index on drop.
        property int draggedIndex: -1
        property int dropIndex: -1

        // Live cursor-following position and appearance for dragGhost
        // below, set from the dragged delegate's onDragStarted/
        // onDragPositionChanged.
        property real dragVisualX: 0
        property real dragVisualY: 0
        property string dragGhostIcon: ""
        property string dragGhostLabel: ""

        // Drop-target placeholder: a themed, accent-tinted outline sitting
        // in the slot the drag would currently land in — "properly colored
        // placeholder where the drop will potentially land." Sits behind
        // everything else (z: -1) and only while a drag is actually
        // happening.
        Rectangle {
            visible: appsContainer.draggedIndex >= 0
            z: -1
            x: appsContainer.dropIndex * appsContainer.buttonAdvance
            y: 0
            width: Theme.iconButtonSize
            height: Theme.iconButtonSize
            radius: Theme.cornerRadius
            color: Theme.accent
            opacity: 0.25
            border.width: 2
            border.color: Theme.accent

            Behavior on x { NumberAnimation { duration: Theme.animationDuration } }
        }

        Repeater {
            id: appsRepeater
            model: root.apps

            delegate: SquareIconButton {
                id: appButton

                required property int index
                required property var modelData

                deletable: true
                draggable: true
                ghosted: appButton.index === appsContainer.draggedIndex

                // Where this button currently belongs on screen: its own
                // slot, unless the drag's target gap has "passed" it, in
                // which case it shifts by one to make room.
                property int displaySlot: {
                    const dragged = appsContainer.draggedIndex
                    const drop = appsContainer.dropIndex
                    if (dragged < 0 || appButton.index === dragged) return appButton.index
                    if (dragged < drop) {
                        return (appButton.index > dragged && appButton.index <= drop) ? appButton.index - 1 : appButton.index
                    }
                    return (appButton.index >= drop && appButton.index < dragged) ? appButton.index + 1 : appButton.index
                }

                // The real button never follows the cursor itself — it
                // stays put (just faded via `ghosted`) at its own,
                // possibly-shifted slot the whole time; dragGhost below is
                // the separate, non-interactive copy that actually follows
                // the cursor. Deliberately not the same item: this button's
                // own MouseArea is what's holding the mouse grab for the
                // entire drag, and changing *this* item's geometry
                // synchronously from within that very MouseArea's own move
                // handler turned out to silently drop the grab after 2-3
                // move events (confirmed via instrumented headless
                // testing — MouseArea.canceled fired, not a scripting
                // artifact). Keeping this item stationary sidesteps that
                // entirely, and matches CLAUDE.md's spec more literally
                // besides ("a small translucent *copy* ... following the
                // cursor" — not the original button itself).
                x: displaySlot * appsContainer.buttonAdvance
                y: 0

                Behavior on x { NumberAnimation { duration: Theme.animationDuration } }

                // modelData.icon (when present — see AddAppDialog.qml,
                // which sets it both for a picked .desktop app and, now,
                // for a manually-entered one too) is either an absolute
                // image path or an icon-theme name; the latter only
                // resolves via the "image://theme/" provider
                // (icon_provider.py), same resolution AddAppDialog.qml's
                // own list uses. Letters are only a fallback for apps with
                // no icon at all.
                iconSource: modelData.icon
                    ? (modelData.icon.startsWith("/") ? modelData.icon : "image://theme/" + modelData.icon)
                    : ""
                label: modelData.icon ? "" : modelData.name.charAt(0).toUpperCase()
                tooltipText: modelData.name

                onClicked: root.launchApp(appButton.index)
                onDeleteRequested: root.removeAppRequested(appButton.index)

                onDragStarted: {
                    appsContainer.draggedIndex = appButton.index
                    appsContainer.dropIndex = appButton.index
                    appsContainer.dragGhostIcon = appButton.iconSource
                    appsContainer.dragGhostLabel = appButton.label
                    appsContainer.dragVisualX = appButton.x
                    appsContainer.dragVisualY = appButton.y
                }
                onDragPositionChanged: (sceneX, sceneY) => {
                    const localPos = appsContainer.mapFromItem(null, sceneX, sceneY)
                    const maxX = Math.max(0, (appsRepeater.count - 1) * appsContainer.buttonAdvance)
                    appsContainer.dragVisualX = Math.max(0, Math.min(maxX, localPos.x - appButton.width / 2))
                    appsContainer.dragVisualY = localPos.y - appButton.height / 2
                    const slot = Math.round(appsContainer.dragVisualX / appsContainer.buttonAdvance)
                    appsContainer.dropIndex = Math.max(0, Math.min(appsRepeater.count - 1, slot))
                }
                onDragFinished: {
                    // Capture into locals and reset the shared drag state
                    // *before* the moveAppRequested() call below, not
                    // after: that call round-trips into Python and back
                    // (clientModel.moveApp() -> dataChanged -> Repeater
                    // re-evaluates `model: root.apps`), which can destroy
                    // and recreate every delegate *synchronously* —
                    // including this very one, mid-handler. Anything
                    // referencing `appsContainer`/`appButton` written
                    // *after* that call would then fail with "appsContainer
                    // is not defined", confirmed by actually triggering it.
                    const fromIndex = appButton.index
                    const toIndex = appsContainer.dropIndex
                    appsContainer.draggedIndex = -1
                    appsContainer.dropIndex = -1
                    if (toIndex !== fromIndex) {
                        root.moveAppRequested(fromIndex, toIndex)
                    }
                }
            }
        }

        // The small translucent copy of the dragged button that actually
        // follows the cursor (see the comment on the delegate's `x` above
        // for why this has to be a separate, non-interactive item rather
        // than the real button moving itself). Purely visual — no
        // MouseArea, never the target of any input.
        Rectangle {
            id: dragGhost
            visible: appsContainer.draggedIndex >= 0
            x: appsContainer.dragVisualX
            y: appsContainer.dragVisualY
            width: Theme.iconButtonSize
            height: Theme.iconButtonSize
            radius: Theme.cornerRadius
            color: Theme.surface
            opacity: 0.6
            border.width: 1
            border.color: Theme.surfaceGlass
            z: 20

            Image {
                anchors.fill: parent
                anchors.margins: Theme.iconMargin
                visible: appsContainer.dragGhostIcon !== ""
                source: appsContainer.dragGhostIcon
                fillMode: Image.PreserveAspectFit
            }

            Text {
                anchors.centerIn: parent
                visible: appsContainer.dragGhostIcon === ""
                text: appsContainer.dragGhostLabel
                color: Theme.textPrimary
                font.pixelSize: Theme.iconGlyphSize
            }
        }
    }

    SquareIconButton {
        label: "+"
        tooltipText: "Add application"
        onClicked: root.addAppRequested()
    }

    Item { Layout.fillWidth: true }
}
