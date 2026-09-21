pragma Singleton
import QtQuick

// Global tracker for which single app button, if any, is armed for
// delete. See docs/comments-details.md [32].
QtObject {
    property var armedButton: null

    function disarmAny() {
        if (armedButton !== null) {
            armedButton.armedForDelete = false
            armedButton = null
        }
    }
}
