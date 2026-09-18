pragma Singleton
import QtQuick

// Tracks which single app button (if any) is currently showing its
// delete/trash-bin affordance, app-wide. Only one button may be "armed"
// for delete at a time; individual SquareIconButton instances don't
// otherwise know about each other, so this is the shared place that lets
// arming one implicitly disarm a previously-armed different one, and lets
// a global cancel (clicking empty background, pressing Escape) reach
// whichever button is currently armed without the caller needing a
// reference to it.
QtObject {
    property var armedButton: null

    function disarmAny() {
        if (armedButton !== null) {
            armedButton.armedForDelete = false
            armedButton = null
        }
    }
}
