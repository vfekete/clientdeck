import QtQuick

// Square image-button — used for every per-client app button, plus assorted
// one-off buttons (theme toggle, zoom, "add client"/"add app").
Rectangle {
    id: root

    property string iconSource: ""
    property string label: ""

    // Empty by default = no tooltip — see docs/comments-details.md [73].
    property string tooltipText: ""
    // Bottom toolbar shows its tooltip above instead — see [74].
    property bool tooltipAbove: false

    // Off by default, so the many non-app uses of this component (theme
    // toggle, zoom +/-, "+" buttons, dialog buttons) are unaffected —
    // see [75].
    property bool draggable: false
    // Opt-in: label glyph always fills 75% of the button — see [76].
    property bool bigLabel: false

    // Plain press+release — see [78].
    signal clicked()
    signal dragStarted()
    signal dragPositionChanged(real sceneX, real sceneY)
    signal dragFinished()

    // True while this button is the one being dragged — see [82].
    property bool ghosted: false

    // implicitWidth/Height, not width/height, for Layout compatibility — see [83].
    implicitWidth: Theme.iconButtonSize
    implicitHeight: Theme.iconButtonSize
    radius: Theme.cornerRadius
    opacity: ghosted ? 0.5 : (enabled ? 1.0 : 0.45)
    // Always solid/opaque, unlike the glass panel behind it — see [84].
    color: mouseArea.pressed
        ? Theme.accent
        : (mouseArea.containsMouse ? Theme.surfaceHover : Theme.surface)
    border.width: 1
    border.color: Theme.surfaceGlass

    Behavior on color { ColorAnimation { duration: Theme.animationDuration } }
    Behavior on opacity { NumberAnimation { duration: Theme.animationDuration } }

    // Grows by a few px on hover, not a scale factor — see [121].
    // Unanimated (instant snap on hover in/out) — see [122].
    readonly property real iconHoverGrow: 3 * Theme.uiScale

    // Fills the button (minus a themed margin) rather than a small fixed
    // size centered in the middle.
    Image {
        anchors.centerIn: parent
        width: (parent.width - Theme.iconMargin * 2) + (mouseArea.containsMouse ? root.iconHoverGrow : 0)
        height: (parent.height - Theme.iconMargin * 2) + (mouseArea.containsMouse ? root.iconHoverGrow : 0)
        visible: root.iconSource !== ""
        source: root.iconSource
        fillMode: Image.PreserveAspectFit
    }

    Text {
        anchors.centerIn: parent
        width: root.bigLabel ? parent.width * 0.75 : implicitWidth
        height: root.bigLabel ? parent.height * 0.75 : implicitHeight
        visible: root.iconSource === ""
        text: root.label
        color: Theme.textPrimary
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        // Text.Fit for bigLabel scaling — see [76].
        fontSizeMode: root.bigLabel ? Text.Fit : Text.FixedSize
        font.pixelSize: root.bigLabel ? 512 : Theme.iconGlyphSize
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        // Prevents the parent Flickable/ScrollView from stealing a drag — see docs/comments-details.md [87].
        preventStealing: true

        readonly property real dragThreshold: 8
        property real pressX: 0
        property real pressY: 0
        property bool dragging: false

        onPressed: (mouse) => {
            pressX = mouse.x
            pressY = mouse.y
            dragging = false
        }

        onPositionChanged: (mouse) => {
            if (root.draggable && !dragging && pressed) {
                const dx = mouse.x - pressX
                const dy = mouse.y - pressY
                if (Math.sqrt(dx * dx + dy * dy) > dragThreshold) {
                    dragging = true
                    root.dragStarted()
                }
            }
            if (dragging) {
                const scenePos = mapToItem(null, mouse.x, mouse.y)
                root.dragPositionChanged(scenePos.x, scenePos.y)
            }
        }

        onReleased: {
            if (dragging) {
                dragging = false
                root.dragFinished()
            } else if (containsMouse) {
                root.clicked()
            }
        }

        onCanceled: {
            if (dragging) {
                dragging = false
                root.dragFinished()
            }
        }
    }

    HoverHandler {
        id: tooltipHoverHandler
        // Passive, coexists with MouseArea's grab — see [93].
    }

    ThemedTooltip {
        parent: root
        x: 0
        y: root.tooltipAbove ? -implicitHeight - Theme.spacing / 2 : root.height + Theme.spacing / 2
        // Hidden during drag — see [94].
        visible: tooltipHoverHandler.hovered && root.tooltipText.length > 0
            && !mouseArea.dragging
        title: root.tooltipText
    }
}
