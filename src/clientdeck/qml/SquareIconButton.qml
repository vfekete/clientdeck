import QtQuick

// Square image-button — used for every per-client app button, plus assorted
// one-off buttons (theme toggle, zoom, "add client"/"add app").
Rectangle {
    id: root

    property string iconSource: ""
    property string label: ""

    // Themed hover tooltip — describes the button's function, or (for a
    // per-client app button) the app's name. Empty by default so a caller
    // that forgets to set it just gets no tooltip rather than a blank one.
    property string tooltipText: ""
    // Most buttons have room to show the tooltip below them; the bottom
    // toolbar (theme/zoom/reset) sits at the very bottom edge of the
    // borderless window, so a tooltip below it would render past the
    // window's own edge and never be visible — those callers set this true.
    property bool tooltipAbove: false

    // Opt-in behaviors — off by default, so the many non-app uses of this
    // component (theme toggle, zoom +/-, "+" buttons, dialog buttons) are
    // unaffected. ClientRow.qml turns both on for actual app buttons.
    property bool deletable: false
    property bool draggable: false
    // Opt-in: makes the `label` glyph always fill 75% of the button's
    // width/height (via fontSizeMode: Text.Fit) instead of the fixed
    // Theme.iconGlyphSize used by every other label (client initials, theme
    // toggle, zoom +/-, reset) — set at call sites that want an
    // oversized glyph, e.g. the per-row "add app" +.
    property bool bigLabel: false

    // Whether pressing *this* button counts as "clicking elsewhere" for
    // any other button currently armed for delete — on by default, since
    // that's the whole point of the click-elsewhere-cancels rule. The
    // theme toggle is the one exception (set false at its call site in
    // Main.qml): switching dark/light is an incidental display
    // preference, not an action on any particular app, so it shouldn't
    // silently cancel an in-progress delete confirmation on some other
    // button.
    property bool cancelsOtherArmedButton: true

    // Fires only for a plain press+release that never armed delete and
    // never turned into a drag — i.e. exactly the old single-signal
    // behavior, unchanged for every caller that doesn't opt into the two
    // behaviors below.
    signal clicked()
    signal deleteRequested()
    signal dragStarted()
    signal dragPositionChanged(real sceneX, real sceneY)
    signal dragFinished()

    // True once a `deletable` button has been held (pressed, not moved
    // away) through the full hold schedule below — see holdTimer.
    // Persists after the mouse is released (showing the trash-bin icon
    // indefinitely); a separate, later click is what actually deletes —
    // see onReleased.
    property bool armedForDelete: false

    // Keeps DeleteArmState.armedButton in sync so the rest of the app can
    // find (and cancel) whichever button is currently armed without a
    // direct reference to it. Also the mechanism behind "arming a second
    // button disarms the first": setting a different button's
    // armedForDelete to false here re-enters this same handler on *that*
    // button, which is harmless since it only clears the registry when it
    // still points at itself.
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

    // Hold timeline for a deletable button, as a list of phase durations
    // (ms): wait 150ms (still could just be a click — no visual change
    // yet), then alternate between the current appearance and the target
    // (opposite) one every 500ms, landing on — and staying on — the
    // target the 4th time it comes around. For arming, that reads as
    // I 150ms, D 500ms, I 500ms, D 500ms, I 500ms, D 500ms, I 500ms, D
    // (permanent) — three temporary blinks of the trash bin, then it
    // commits. Disarming an already-armed button mirrors this exactly
    // (same schedule, same code) since `visualArmed` below just alternates
    // between whatever `armedForDelete` currently is and its opposite —
    // it always ends on "original icon" instead just because
    // armedForDelete started `true` this time.
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

    // True while this specific button is the one currently being dragged
    // (set externally by whatever positions it, e.g. ClientRow.qml) — a
    // dedicated property rather than letting a caller just override
    // `opacity` directly at instantiation, which would silently replace
    // (not combine with) the enabled/disabled dimming below — the exact
    // same class of "external binding silently wins" surprise documented
    // for implicitWidth/height above.
    property bool ghosted: false

    // implicitWidth/Height, not width/height: this component is used both
    // standalone (Item.width defaults to implicitWidth there) and as a
    // direct child of a RowLayout (ClientRow, the bottom toolbar) — a
    // Layout only reactively tracks a child's implicitWidth/implicitHeight
    // (or Layout.preferredWidth/Height) for its size, not a plain `width:`
    // binding. Using plain `width:` here/at call sites looked fine
    // initially but silently stopped reacting to Theme.uiScale changes
    // once placed in a Layout, while `radius` (not Layout-managed) kept
    // scaling — the actual cause of buttons turning circular after
    // zooming, confirmed by inspecting live property values.
    implicitWidth: Theme.iconButtonSize
    implicitHeight: Theme.iconButtonSize
    radius: Theme.cornerRadius
    opacity: ghosted ? 0.5 : (enabled ? 1.0 : 0.45)
    // Solid/opaque in every state — unlike the main window's glass panel
    // behind it, a button's own fill never fades with hover-driven
    // background opacity; only the background is meant to do that.
    // Armed-for-delete still gets its own hover feedback (a lighter/more
    // saturated red), same as every other state — it shouldn't be the one
    // state that looks static under the cursor.
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
        // Text.Fit scales the glyph up to fill the 75%-of-button box above
        // exactly, however big/small the button ends up (window resize,
        // Theme.uiScale zoom, …) — a fixed pixelSize couldn't guarantee
        // "always 75%" across those.
        fontSizeMode: root.bigLabel ? Text.Fit : Text.FixedSize
        font.pixelSize: root.bigLabel ? 512 : Theme.iconGlyphSize
    }

    Text {
        anchors.centerIn: parent
        visible: root.visualArmed
        text: "🗑"
        color: Theme.textPrimary
        // 100% bigger than the normal icon/letter glyph size — a plain
        // letter or app icon reads fine at the normal size, but the trash
        // bin is the one state meant to read as an unambiguous warning at
        // a glance.
        font.pixelSize: Theme.iconGlyphSize * 2
    }

    // Walks through `holdSchedule` one phase at a time (variable interval
    // per phase, hence manual restart() rather than `repeat: true`).
    // Reaching the end of the schedule is the actual arm/disarm moment;
    // every phase before that is purely visual (see `blinking` above). A
    // released-before-the-end press is a *click* instead, handled entirely
    // in onReleased below via `holdTimer.running`.
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
        // Every app row lives inside Main.qml's ScrollView, which wraps
        // its content in a Flickable — Flickable steals an in-progress
        // mouse grab from a child MouseArea once movement exceeds its own
        // small drag threshold, mistaking a button drag for a scroll
        // gesture. Confirmed by instrumented headless testing: without
        // this, MouseArea.canceled fired reliably ~15-20px into any drag
        // (a single big instantaneous jump didn't trigger it — Flickable's
        // steal heuristic needs a short *sequence* of incremental moves,
        // which is exactly what a real mouse produces and what real users
        // were hitting). This is the standard, documented fix for a
        // draggable MouseArea nested inside a Flickable/ScrollView.
        preventStealing: true

        readonly property real dragThreshold: 8
        property real pressX: 0
        property real pressY: 0
        property bool dragging: false
        // Snapshot of armedForDelete at the start of *this* press — decides
        // what a short click (release before the hold timer fires) means:
        // delete-confirm if the button was already armed, or the normal
        // click/launch action otherwise. Needed because onTriggered may
        // flip armedForDelete mid-press, and by release time the live value
        // no longer reflects what it was when this press began.
        property bool armedAtPressStart: false

        onPressed: (mouse) => {
            pressX = mouse.x
            pressY = mouse.y
            dragging = false
            armedAtPressStart = root.armedForDelete
            // Pressing anywhere else — including on another armed-for-
            // delete button — is a "click elsewhere", which cancels that
            // other button's armed state (does not affect this button) —
            // unless this button opted out (see cancelsOtherArmedButton).
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
            // A non-deletable button has no hold concept at all, so every
            // release is a click. A deletable button's holdTimer still
            // *running* at release means this press ended before the hold
            // schedule finished — i.e. it was a plain click too. If the
            // schedule had already completed, armedForDelete was already
            // toggled and this release is just the end of that hold;
            // nothing further happens.
            const wasClick = !root.deletable || holdTimer.running
            root.stopHoldAnimation()
            if (dragging) {
                dragging = false
                root.dragFinished()
            } else if (containsMouse && wasClick) {
                if (armedAtPressStart) {
                    // A click while already armed is the explicit delete
                    // confirmation — reset first (see DeleteArmState's own
                    // comment on this ordering) since deleteRequested() can
                    // destroy this delegate synchronously.
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

        // Leaving the button area while a hold is in progress cancels just
        // that hold (per "do not move the cursor outside button area") —
        // armedForDelete itself is untouched, since a hold that never
        // completed never changed it. Not applied to hover-only exits
        // (mouse not pressed) or to an already-started drag, which is
        // expected to roam outside this button's own bounds.
        onExited: {
            if (pressed && !dragging) {
                root.stopHoldAnimation()
            }
        }
    }

    HoverHandler {
        id: tooltipHoverHandler
        // MouseArea above already grabs press/drag; a HoverHandler is
        // passive (hover-only, never grabs), so the two coexist without
        // interfering — same pattern already used for the client logo's
        // tooltip in ClientRow.qml.
    }

    ThemedTooltip {
        parent: root
        x: 0
        y: root.tooltipAbove ? -implicitHeight - Theme.spacing / 2 : root.height + Theme.spacing / 2
        // Never during an active drag/delete-arm sequence (including a
        // mid-hold blink frame that's currently *showing* the armed look)
        // — a tooltip fighting for attention with the ghost or the
        // trash-bin icon would just be noise.
        visible: tooltipHoverHandler.hovered && root.tooltipText.length > 0
            && !root.visualArmed && !mouseArea.dragging
        title: root.tooltipText
    }
}
