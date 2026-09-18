pragma Singleton
import QtQuick

// Central definition of the app's dark/light glass theme (colors, corner
// radius, motion timing) — per CLAUDE.md, kept centralized rather than
// hardcoded per-component so the "consistent dark theme" requirement (now
// "consistent theme" for either mode) is enforceable in one place.
//
// Every color below is a *binding* on `isDark`, not a literal — flipping
// `Theme.isDark` (e.g. from the main window's theme-toggle button) makes
// every component using these tokens repaint reactively, with no other
// code needing to know a theme switch happened.
QtObject {
    property bool isDark: true

    readonly property color background: isDark ? "#14161c" : "#f4f5f7"
    // Light theme: a soft off-white rather than literal pure white
    // ("#ffffff" read as too stark/full-white against the rest of the
    // theme's muted tones).
    readonly property color surface: isDark ? "#1c1f28" : "#f2f3f6"
    // Solid (not translucent) hover step up from `surface` — for things
    // like SquareIconButton, which must stay fully opaque in every state
    // rather than fading with the background's own hover-driven opacity.
    readonly property color surfaceHover: isDark ? "#262a37" : "#e6e8ed"
    readonly property color surfaceGlass: isDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05)

    // Translucent panel fill for the main window (which is itself a
    // transparent, borderless surface) and other glass-styled overlays
    // like ThemedTooltip — distinct from surfaceGlass, which is meant for
    // subtle highlights on top of an already-opaque surface.
    //
    // Split into base RGB + two alpha levels (rather than one fixed
    // `glassPanel` color) so the main window can animate its own panel
    // between them on hover (see Main.qml) without needing its own copy
    // of the base color, and without that hover state leaking into other
    // glassPanel users like ThemedTooltip, which always render at the
    // resting alpha.
    readonly property color glassPanelBase: isDark ? Qt.rgba(0.078, 0.086, 0.106, 1) : Qt.rgba(0.93, 0.938, 0.953, 1)
    readonly property real glassPanelAlpha: isDark ? 0.78 : 0.72
    readonly property real glassPanelHoverAlpha: isDark ? 0.96 : 0.94
    readonly property color glassPanel: Qt.rgba(glassPanelBase.r, glassPanelBase.g, glassPanelBase.b, glassPanelAlpha)

    // The main window's panel fades top-to-bottom (linear, top more
    // opaque) rather than one flat alpha — this is the bottom edge's
    // alpha as a fraction of whatever the top's current alpha is (resting
    // or hovered), so the same ratio applies in both states without
    // needing separate top/bottom tokens per state. Easy single knob to
    // retune (or drop entirely) if the linear gradient doesn't read well.
    readonly property real glassPanelBottomRatio: 0.5

    readonly property color accent: "#7c5cff"
    readonly property color accentHover: "#9578ff"
    readonly property color textPrimary: isDark ? "#f2f2f5" : "#1b1d22"
    readonly property color textSecondary: isDark ? "#9a9db0" : "#5b5e6b"
    readonly property color danger: isDark ? "#ff5470" : "#d92a49"
    // Hover step for a `danger`-colored surface (the armed-for-delete
    // button) — same "push further from the background" direction as
    // surface/surfaceHover: lighter in dark mode, darker/more saturated in
    // light mode, so hovering the trash-bin button gives feedback just
    // like every other button state does.
    readonly property color dangerHover: isDark ? "#ff7088" : "#c01f3c"
    readonly property color dangerSurface: isDark ? Qt.rgba(1, 0.32, 0.44, 0.12) : Qt.rgba(0.85, 0.16, 0.29, 0.1)

    // --- UI zoom ------------------------------------------------------
    // A single scale factor everything size-related is derived from, so
    // "zoom in/out" (the bottom-left +/- buttons and Ctrl+/Ctrl-) scales
    // fonts, button sizes, spacing, and corner radius all together,
    // keeping the whole layout proportionally identical, just bigger or
    // smaller — see Main.qml for the buttons/shortcuts and the
    // window-growth behavior that goes with this.
    property real uiScale: 1.0
    readonly property real minUiScale: 0.75
    readonly property real maxUiScale: 2.0
    readonly property real uiScaleStep: 0.1

    function zoomIn() {
        uiScale = Math.min(maxUiScale, Math.round((uiScale + uiScaleStep) * 100) / 100)
    }
    function zoomOut() {
        uiScale = Math.max(minUiScale, Math.round((uiScale - uiScaleStep) * 100) / 100)
    }
    function resetZoom() {
        uiScale = 1.0
    }

    readonly property real cornerRadius: 14 * uiScale
    readonly property real spacing: 12 * uiScale
    readonly property int animationDuration: 160

    // Reusable scaled sizes, so every component that needs one of these
    // shares the same scaling rather than each hardcoding its own
    // `* Theme.uiScale` (and risking missing one on a future edit).
    readonly property real iconButtonSize: 64 * uiScale
    readonly property real smallIconButtonSize: 40 * uiScale
    readonly property real hugeIconButtonSize: 96 * uiScale
    readonly property real iconGlyphSize: Math.round(20 * uiScale)
    // SquareIconButton's own icon image now fills the button minus this
    // margin on every side (was a small fixed-size icon centered in a
    // much bigger button) — scales with zoom like every other size here.
    readonly property real iconMargin: 4 * uiScale
    readonly property real logoSize: 48 * uiScale
    readonly property real rowHeight: 72 * uiScale

    readonly property int fontSizeSmall: Math.round(11 * uiScale)
    readonly property int fontSizeBody: Math.round(13 * uiScale)
    readonly property int fontSizeMedium: Math.round(15 * uiScale)
    readonly property int fontSizeLarge: Math.round(18 * uiScale)

    readonly property real fieldPadding: 10 * uiScale
    readonly property real fieldRightPadding: 30 * uiScale
}
