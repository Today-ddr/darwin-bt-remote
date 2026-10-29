import Foundation

enum AppSettings {
    static let touchpadSensitivityKey = "BTRemote.touchpadSensitivity"
    static let scrollSensitivityKey = "BTRemote.scrollSensitivity"
    static let autoAdvertiseKey = "BTRemote.autoAdvertise"
    /// Raw value of `AppTheme`; unknown or absent values read as `.system`.
    static let colorSchemeKey = "BTRemote.colorScheme"
    static let developerModeKey = "BTRemote.developerMode"
    static let useServiceChangedKey = "BTRemote.useServiceChanged"
    static let deviceNamesKey = "BTRemote.deviceNames"
    /// UUID strings of the hosts the user removed; a removal has to outlive the launch that made it
    static let blockedCentralsKey = "BTRemote.blockedCentrals"
    static let hasSeenWelcomeKey = "BTRemote.hasSeenWelcome"
    /// Raw value of `InputPage`; the last page shown in the input tab.
    static let inputPageKey = "BTRemote.inputPage"
    static let advertisedNameKey = "BTRemote.advertisedName"
    static let invertScrollKey = "BTRemote.invertScroll"
    static let pinchGestureActionKey = "BTRemote.pinchGestureAction"
    static let threeFingerSwipeUpKey = "BTRemote.threeFingerSwipeUp"
    static let threeFingerSwipeDownKey = "BTRemote.threeFingerSwipeDown"
    static let threeFingerSwipeLeftKey = "BTRemote.threeFingerSwipeLeft"
    static let threeFingerSwipeRightKey = "BTRemote.threeFingerSwipeRight"
    static let threeFingerTapKey = "BTRemote.threeFingerTap"
    static let fourFingerSwipeUpKey = "BTRemote.fourFingerSwipeUp"
    static let fourFingerSwipeDownKey = "BTRemote.fourFingerSwipeDown"
    static let fourFingerSwipeLeftKey = "BTRemote.fourFingerSwipeLeft"
    static let fourFingerSwipeRightKey = "BTRemote.fourFingerSwipeRight"
    static let fourFingerTapKey = "BTRemote.fourFingerTap"
    static let rotationGestureActionKey = "BTRemote.rotationGestureAction"
    static let doubleTapDragKey = "BTRemote.doubleTapDrag"
    static let longPressDragKey = "BTRemote.longPressDrag"
    static let hapticsEnabledKey = "BTRemote.hapticsEnabled"
    static let hapticsTrackpadKey = "BTRemote.hapticsTrackpad"
    static let hapticsKeyboardKey = "BTRemote.hapticsKeyboard"
    static let hapticsScrollKey = "BTRemote.hapticsScroll"
    /// Raw value of `Haptics.Intensity`; unknown or absent values read as `.medium`.
    static let hapticsIntensityKey = "BTRemote.hapticsIntensity"

    static let maxAdvertisedNameLength = 26

    static let repoURL = URL(string: "https://github.com/jqssun/darwin-bt-remote")!
    static let instructionsURL = URL(string: "https://github.com/jqssun/darwin-bt-remote/blob/main/README.md")!

    static let defaultPointerSensitivity = 5.0
    static let pointerSensitivityRange = 0.5 ... 10.0
    static let defaultScrollSensitivity = 1.0
    static let scrollSensitivityRange = 0.5 ... 3.0
}

/// The default binding of every trackpad gesture, in one place.
///
/// A gesture needs a default in two places: the picker shows one when the user
/// has never chosen (`TrackpadGestureSettingsView`) and the recognizer applies
/// one when nothing is stored (`TouchpadView`). Both sides read this table so a
/// drift between two copies cannot make the picker name one action while the
/// gesture performs another.
///
/// These defaults follow Apple platform semantics: Mission Control, App Exposé
/// and switching Spaces are macOS gestures, and the controlled Mac is the
/// device this app targets.
enum GestureDefaults {
    /// Pinch keeps zoom: `Cmd+=` / `Cmd+-` is the closest a keyboard can come
    /// to a continuous pinch.
    static let pinch = TrackpadGestureAction.zoom
    /// Rotation is off, not remapped. A rotation event reports an angle, and
    /// HID keyboard and mouse reports cannot express one, so any binding here
    /// is a guess.
    static let rotation = TrackpadGestureAction.none

    static let threeFingerSwipeUp = TrackpadGestureAction.missionControl
    static let threeFingerSwipeDown = TrackpadGestureAction.appExpose
    static let threeFingerSwipeLeft = TrackpadGestureAction.switchSpaceLeft
    static let threeFingerSwipeRight = TrackpadGestureAction.switchSpaceRight
    static let threeFingerTap = TrackpadGestureAction.none

    /// Four fingers use the same macOS semantics as three, so a gesture does
    /// not change meaning with the number of fingers used for it.
    static let fourFingerSwipeUp = TrackpadGestureAction.missionControl
    static let fourFingerSwipeDown = TrackpadGestureAction.appExpose
    static let fourFingerSwipeLeft = TrackpadGestureAction.switchSpaceLeft
    static let fourFingerSwipeRight = TrackpadGestureAction.switchSpaceRight
    static let fourFingerTap = TrackpadGestureAction.none
}
