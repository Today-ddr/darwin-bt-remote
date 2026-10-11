import Foundation

enum AppSettings {
    static let touchpadSensitivityKey = "BTRemote.touchpadSensitivity"
    static let scrollSensitivityKey = "BTRemote.scrollSensitivity"
    static let autoAdvertiseKey = "BTRemote.autoAdvertise"
    static let colorSchemeKey = "BTRemote.colorScheme"
    static let developerModeKey = "BTRemote.developerMode"
    static let useServiceChangedKey = "BTRemote.useServiceChanged"
    static let deviceNamesKey = "BTRemote.deviceNames"
    static let hasSeenWelcomeKey = "BTRemote.hasSeenWelcome"
    static let liveTypingKey = "BTRemote.liveTyping"
    static let remoteModeKey = "BTRemote.remoteMode"
    static let advertisedNameKey = "BTRemote.advertisedName"
    static let precisionTouchpadKey = "BTRemote.precisionTouchpad"
    static let naturalScrollKey = "BTRemote.naturalScroll"
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
    static let hapticsEnabledKey = "BTRemote.hapticsEnabled"
    static let hapticsTrackpadKey = "BTRemote.hapticsTrackpad"
    static let hapticsKeyboardKey = "BTRemote.hapticsKeyboard"
    static let hapticsScrollKey = "BTRemote.hapticsScroll"
    /// Raw value of `Haptics.Intensity`; unknown or absent values read as `.strong`.
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
/// one when nothing is stored (`TouchpadView`). Those used to each spell the
/// value out, and a drift between two copies is invisible on screen — the
/// picker would name one action while the gesture performed another. Both sides
/// read this table instead.
///
/// These defaults follow Apple platform semantics, and four of them are
/// macOS-only chords (Mission Control, App Exposé, switching Spaces). The
/// controlled device is not necessarily an Apple device — it may be Windows,
/// Linux, Android or tvOS, where `Ctrl`+arrow means something else or nothing
/// at all — and nothing here can detect that, so treat these as Apple-host
/// defaults rather than universal ones.
enum GestureDefaults {
    /// Pinch keeps zoom: `Cmd+=` / `Cmd+-` is the closest a keyboard can come
    /// to a continuous pinch, and the continuous path lives in
    /// `TrackpadPanel.handlePinchZoom`.
    static let pinch = TrackpadGestureAction.zoom
    /// Rotation is off, not remapped. A rotation event reports an angle, and
    /// HID keyboard and mouse reports cannot express one, so any binding here
    /// is a guess. The guess it used to fall back to was `rotateRight`, which
    /// sends `Cmd+R` — the frontmost app's refresh/restart shortcut — so a
    /// stray two-finger turn could reload or restart whatever app was in front.
    static let rotation = TrackpadGestureAction.none

    static let threeFingerSwipeUp = TrackpadGestureAction.appSwitcher
    static let threeFingerSwipeDown = TrackpadGestureAction.home
    static let threeFingerSwipeLeft = TrackpadGestureAction.previousApp
    static let threeFingerSwipeRight = TrackpadGestureAction.nextApp
    static let threeFingerTap = TrackpadGestureAction.spotlight

    /// Four fingers, macOS semantics: Mission Control, App Exposé and Spaces,
    /// which are the `Ctrl`+arrow chords rather than the iPadOS ones the
    /// three-finger row uses.
    static let fourFingerSwipeUp = TrackpadGestureAction.missionControl
    static let fourFingerSwipeDown = TrackpadGestureAction.appExpose
    static let fourFingerSwipeLeft = TrackpadGestureAction.switchSpaceLeft
    static let fourFingerSwipeRight = TrackpadGestureAction.switchSpaceRight
    static let fourFingerTap = TrackpadGestureAction.controlCenter
}
