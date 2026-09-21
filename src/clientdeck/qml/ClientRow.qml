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

        // Opens the "modify client" dialog. TapHandler, not MouseArea — see [54].
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

    // Plain Item + Repeater, not a Row — see docs/comments-details.md [55].
    Item {
        id: appsContainer

        // Hidden (not just empty) when there are no apps — see [56].
        visible: root.apps.length > 0

        readonly property real buttonAdvance: Theme.iconButtonSize + Theme.spacing
        // Computed and reported manually for the outer RowLayout — see [57].
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

        // Drop-target placeholder — see [58].
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

                // Stays put (just faded); dragGhost is the copy that follows the cursor — see [59].
                x: displaySlot * appsContainer.buttonAdvance
                y: 0

                Behavior on x { NumberAnimation { duration: Theme.animationDuration } }

                // Icon path/theme-name resolution — see [60].
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
                    // Locals captured, drag state reset, before moveAppRequested() — see [61].
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

        // The small translucent copy that follows the cursor — see [62].
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
        bigLabel: true
        tooltipText: "Add application"
        onClicked: root.addAppRequested()
    }

    Item { Layout.fillWidth: true }
}
