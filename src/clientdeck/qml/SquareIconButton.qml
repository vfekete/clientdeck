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

    // Opt-in, off by default — see [75].
    property bool deletable: false
    property bool draggable: false
    // Opt-in: label glyph always fills 75% of the button — see [76].
    property bool bigLabel: false

    // Whether pressing this button disarms another armed-for-delete button — see [77].
    property bool cancelsOtherArmedButton: true

    // Plain press+release only, not delete-arm/drag — see [78].
    signal clicked()
    signal deleteRequested()
    signal dragStarted()
    signal dragPositionChanged(real sceneX, real sceneY)
    signal dragFinished()

    // True once held through the full hold schedule — see [79].
    property bool armedForDelete: false

    // Keeps DeleteArmState.armedButton in sync — see [80].
    onArmedForDeleteChanged: {
        if (armedForDelete) {
            if (DeleteArmState.armedButton !== null && DeleteArmState.armedButton !== root) {
                DeleteArmState.armedButton.armedForDelete = false
            }
            DeleteArmState.armedButton = root
        } else if (DeleteArmState.armedButton === root) {
            DeleteArmState.armedButton = null
        }
    }

    // Hold timeline (ms per phase) for arm/disarm blinking — see [81].
    readonly property var holdSchedule: [1000, 250, 250, 250, 250]
    property int holdPhase: 0
    property bool blinking: false
    property bool blinkShowTarget: false
    // What's actually rendered: the steady armedForDelete value normally,
    // or — while blinking — alternating between that and its opposite.
    readonly property bool visualArmed: blinking
        ? (blinkShowTarget ? !armedForDelete : armedForDelete)
        : armedForDelete

    function startHoldAnimation() {
        holdPhase = 0
        blinking = false
        blinkShowTarget = false
        holdTimer.interval = holdSchedule[0]
        holdTimer.restart()
    }

    function stopHoldAnimation() {
        holdTimer.stop()
        holdPhase = 0
        blinking = false
        blinkShowTarget = false
    }

    // True while this button is the one being dragged — see [82].
    property bool ghosted: false

    // implicitWidth/Height, not width/height, for Layout compatibility — see [83].
    implicitWidth: Theme.iconButtonSize
    implicitHeight: Theme.iconButtonSize
    radius: Theme.cornerRadius
    opacity: ghosted ? 0.5 : (enabled ? 1.0 : 0.45)
    // Always solid/opaque, unlike the glass panel behind it — see [84].
    color: root.visualArmed
        ? (mouseArea.containsMouse ? Theme.dangerHover : Theme.danger)
        : (mouseArea.pressed
            ? Theme.accent
            : (mouseArea.containsMouse ? Theme.surfaceHover : Theme.surface))
    border.width: 1
    border.color: Theme.surfaceGlass

    Behavior on color { ColorAnimation { duration: Theme.animationDuration } }
    Behavior on opacity { NumberAnimation { duration: Theme.animationDuration } }

    // Fills the button (minus a themed margin) rather than a small fixed
    // size centered in the middle.
    Image {
        anchors.fill: parent
        anchors.margins: Theme.iconMargin
        visible: root.iconSource !== "" && !root.visualArmed
        source: root.iconSource
        fillMode: Image.PreserveAspectFit
    }

    Text {
        anchors.centerIn: parent
        width: root.bigLabel ? parent.width * 0.75 : implicitWidth
        height: root.bigLabel ? parent.height * 0.75 : implicitHeight
        visible: root.iconSource === "" && !root.visualArmed
        text: root.label
        color: Theme.textPrimary
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        // Text.Fit for bigLabel scaling — see [76].
        fontSizeMode: root.bigLabel ? Text.Fit : Text.FixedSize
        font.pixelSize: root.bigLabel ? 512 : Theme.iconGlyphSize
    }

    Text {
        anchors.centerIn: parent
        visible: root.visualArmed
        text: "🗑"
        color: Theme.textPrimary
        // 2x normal glyph size, to read as an unambiguous warning — see [85].
        font.pixelSize: Theme.iconGlyphSize * 2
    }

    // Walks through holdSchedule one phase at a time — see [86].
    Timer {
        id: holdTimer
        onTriggered: {
            root.holdPhase += 1
            if (root.holdPhase >= root.holdSchedule.length) {
                root.stopHoldAnimation()
                root.armedForDelete = !root.armedForDelete
            } else {
                root.blinking = true
                root.blinkShowTarget = !root.blinkShowTarget
                holdTimer.interval = root.holdSchedule[root.holdPhase]
                holdTimer.restart()
            }
        }
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
        // Snapshot of armedForDelete at press start — see [88].
        property bool armedAtPressStart: false

        onPressed: (mouse) => {
            pressX = mouse.x
            pressY = mouse.y
            dragging = false
            armedAtPressStart = root.armedForDelete
            // Disarms another armed button, "click elsewhere" — see [89].
            if (root.cancelsOtherArmedButton
                    && DeleteArmState.armedButton !== null
                    && DeleteArmState.armedButton !== root) {
                DeleteArmState.armedButton.armedForDelete = false
            }
            if (root.deletable) {
                root.startHoldAnimation()
            }
        }

        onPositionChanged: (mouse) => {
            if (root.draggable && !dragging && pressed) {
                const dx = mouse.x - pressX
                const dy = mouse.y - pressY
                if (Math.sqrt(dx * dx + dy * dy) > dragThreshold) {
                    dragging = true
                    root.stopHoldAnimation()
                    root.armedForDelete = false
                    root.dragStarted()
                }
            }
            if (dragging) {
                const scenePos = mapToItem(null, mouse.x, mouse.y)
                root.dragPositionChanged(scenePos.x, scenePos.y)
            }
        }

        onReleased: {
            // Whether this release is a plain click — see [90].
            const wasClick = !root.deletable || holdTimer.running
            root.stopHoldAnimation()
            if (dragging) {
                dragging = false
                root.dragFinished()
            } else if (containsMouse && wasClick) {
                if (armedAtPressStart) {
                    // Reset before emitting — see [91].
                    root.armedForDelete = false
                    root.deleteRequested()
                } else {
                    root.clicked()
                }
            }
        }

        onCanceled: {
            root.stopHoldAnimation()
            if (dragging) {
                dragging = false
                root.dragFinished()
            }
        }

        // Cancels only an in-progress hold, not armedForDelete itself — see [92].
        onExited: {
            if (pressed && !dragging) {
                root.stopHoldAnimation()
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
        // Hidden during drag/delete-arm — see [94].
        visible: tooltipHoverHandler.hovered && root.tooltipText.length > 0
            && !root.visualArmed && !mouseArea.dragging
        title: root.tooltipText
    }
}
