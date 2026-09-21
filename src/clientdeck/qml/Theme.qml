pragma Singleton
import QtQuick

// App's dark/light glass theme tokens, centralized. See docs/comments-details.md [23].
QtObject {
    property bool isDark: true

    readonly property color background: isDark ? "#14161c" : "#f4f5f7"
    // Off-white, not pure white — see [24].
    readonly property color surface: isDark ? "#1c1f28" : "#f2f3f6"
    // Solid hover step, unlike surfaceGlass — see [25].
    readonly property color surfaceHover: isDark ? "#262a37" : "#e6e8ed"
    readonly property color surfaceGlass: isDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05)

    // Translucent panel fill (main window, ThemedTooltip). See [26].
    readonly property color glassPanelBase: isDark ? Qt.rgba(0.078, 0.086, 0.106, 1) : Qt.rgba(0.93, 0.938, 0.953, 1)
    readonly property real glassPanelAlpha: isDark ? 0.78 : 0.72
    readonly property real glassPanelHoverAlpha: isDark ? 0.96 : 0.94
    readonly property color glassPanel: Qt.rgba(glassPanelBase.r, glassPanelBase.g, glassPanelBase.b, glassPanelAlpha)

    // Bottom-edge alpha as a fraction of the top's — see [27].
    readonly property real glassPanelBottomRatio: 0.5

    readonly property color accent: "#7c5cff"
    readonly property color accentHover: "#9578ff"
    readonly property color textPrimary: isDark ? "#f2f2f5" : "#1b1d22"
    readonly property color textSecondary: isDark ? "#9a9db0" : "#5b5e6b"
    readonly property color danger: isDark ? "#ff5470" : "#d92a49"
    // Same hover direction as surface/surfaceHover — see [28].
    readonly property color dangerHover: isDark ? "#ff7088" : "#c01f3c"
    readonly property color dangerSurface: isDark ? Qt.rgba(1, 0.32, 0.44, 0.12) : Qt.rgba(0.85, 0.16, 0.29, 0.1)

    // --- UI zoom ------------------------------------------------------
    // Single scale factor everything size-related derives from — see [29].
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

    // Reusable scaled sizes, shared rather than each component hardcoding
    // its own `* Theme.uiScale` — see [30].
    readonly property real iconButtonSize: 64 * uiScale
    readonly property real smallIconButtonSize: 40 * uiScale
    readonly property real hugeIconButtonSize: 96 * uiScale
    readonly property real iconGlyphSize: Math.round(20 * uiScale)
    // Margin SquareIconButton's icon image fills inside of — see [31].
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
