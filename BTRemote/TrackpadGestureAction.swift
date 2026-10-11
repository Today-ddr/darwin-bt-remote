import SwiftUI

enum TrackpadGestureAction: String, CaseIterable, Identifiable {
    case none = "none"
    case appSwitcher = "app_switcher"
    case home = "home"
    case dock = "dock"
    case previousApp = "previous_app"
    case nextApp = "next_app"
    case spotlight = "spotlight"
    case controlCenter = "control_center"
    case notificationCenter = "notification_center"
    case missionControl = "mission_control"
    case appExpose = "app_expose"
    case switchSpaceLeft = "switch_space_left"
    case switchSpaceRight = "switch_space_right"
    case screenshot = "screenshot"
    case middleClick = "middle_click"
    case zoom = "zoom"
    case rotateLeft = "rotate_left"
    case rotateRight = "rotate_right"

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .none: L10n.Gesture.actionNone
        case .appSwitcher: L10n.Gesture.actionAppSwitcher
        case .home: L10n.Gesture.actionHome
        case .dock: L10n.Gesture.actionDock
        case .previousApp: L10n.Gesture.actionPreviousApp
        case .nextApp: L10n.Gesture.actionNextApp
        case .spotlight: L10n.Gesture.actionSpotlight
        case .controlCenter: L10n.Gesture.actionControlCenter
        case .notificationCenter: L10n.Gesture.actionNotificationCenter
        // These four are new, so `L10n.swift` has no accessor for them yet.
        // The keys are spelled out here rather than in a placeholder accessor
        // so that the only thing still to do is the catalog entry: once
        // `gesture.action_mission_control` and its three neighbours exist in
        // `Localizable.xcstrings`, these lines already resolve to them.
        case .missionControl: "gesture.action_mission_control"
        case .appExpose: "gesture.action_app_expose"
        case .switchSpaceLeft: "gesture.action_switch_space_left"
        case .switchSpaceRight: "gesture.action_switch_space_right"
        case .screenshot: L10n.Gesture.actionScreenshot
        case .middleClick: L10n.Gesture.actionMiddleClick
        case .zoom: L10n.Gesture.actionZoom
        case .rotateLeft: L10n.Gesture.actionRotateLeft
        case .rotateRight: L10n.Gesture.actionRotateRight
        }
    }

    /// Every case sends what this says, and this says what every case sends:
    /// it is derived from `chord` rather than written out beside it, so the two
    /// cannot drift the way the old hand-written table did — it advertised
    /// `Cmd+L` for `rotateLeft` while `execute` sent `Cmd+Alt+R`, and `Globe+A`
    /// for `dock` while `execute` sent `Ctrl+Alt+A`.
    ///
    /// The chord names the key a Mac keyboard prints (`⌘R`), because the device
    /// being controlled is not always a Mac. Where the mapping only makes sense
    /// on one platform the title says so; nothing here claims to be universal.
    var shortcutHint: String {
        guard let chord else { return "" }
        return chord.hint
    }

    /// The keyboard/mouse report this action sends, or `nil` for the actions
    /// that send nothing at all. This is the single source of truth behind both
    /// `execute` and `shortcutHint`.
    var chord: GestureChord? {
        switch self {
        case .none:
            nil
        case .appSwitcher:
            GestureChord(key: .upArrow, modifiers: [.leftGUI])
        case .home:
            GestureChord(key: .h, modifiers: [.leftGUI])
        case .dock:
            GestureChord(key: .a, modifiers: [.leftCtrl, .leftAlt])
        case .previousApp:
            GestureChord(key: .tab, modifiers: [.leftGUI, .leftShift])
        case .nextApp:
            GestureChord(key: .tab, modifiers: [.leftGUI])
        case .spotlight:
            GestureChord(key: .space, modifiers: [.leftGUI])
        case .controlCenter:
            GestureChord(key: .c, modifiers: [.leftCtrl, .leftAlt])
        case .notificationCenter:
            GestureChord(key: .n, modifiers: [.leftCtrl, .leftAlt])
        case .missionControl:
            GestureChord(key: .upArrow, modifiers: [.leftCtrl])
        case .appExpose:
            GestureChord(key: .downArrow, modifiers: [.leftCtrl])
        case .switchSpaceLeft:
            GestureChord(key: .leftArrow, modifiers: [.leftCtrl])
        case .switchSpaceRight:
            GestureChord(key: .rightArrow, modifiers: [.leftCtrl])
        case .screenshot:
            GestureChord(key: .digit3, modifiers: [.leftGUI, .leftShift])
        case .middleClick:
            GestureChord(button: .middle)
        case .zoom:
            // One key, not two: a picker entry can only mean one chord, and
            // zoom-in is the direction a spread performs. The continuous path
            // that really does zoom both ways is
            // `TrackpadPanel.handlePinchZoom`, which never reaches `execute`.
            GestureChord(key: .equal, modifiers: [.leftGUI])
        case .rotateLeft:
            GestureChord(key: .r, modifiers: [.leftGUI, .leftAlt])
        case .rotateRight:
            GestureChord(key: .r, modifiers: [.leftGUI])
        }
    }

    @MainActor
    func execute(hid: HIDInput) {
        guard let chord else { return }
        if let button = chord.button {
            hid.click(button)
        } else if let key = chord.key {
            hid.tap(key, modifiers: chord.modifiers)
        }
    }
}

/// What a `TrackpadGestureAction` presses: either a mouse button or a single
/// key chord, matching the two things `HIDInput` can do. It exists so that what
/// an action sends and what its hint claims are read from one value and cannot
/// drift apart.
struct GestureChord {
    var key: Keycode?
    var modifiers: KeyboardModifiers
    var button: MouseButtons?

    init(key: Keycode, modifiers: KeyboardModifiers = []) {
        self.key = key
        self.modifiers = modifiers
        button = nil
    }

    init(button: MouseButtons) {
        key = nil
        modifiers = []
        self.button = button
    }

    /// The chord as a Mac key cap prints it — modifiers in Apple's order, then
    /// the key. `⌘` is the key an Apple keyboard labels Command, which a PC
    /// keyboard reaches through the Windows key.
    var hint: String {
        if let button {
            return button == .middle ? "Mouse Middle Button" : ""
        }
        guard let key else { return "" }
        var symbols = ""
        if modifiers.contains(.leftCtrl) { symbols += "⌃" }
        if modifiers.contains(.leftAlt) { symbols += "⌥" }
        if modifiers.contains(.leftShift) { symbols += "⇧" }
        if modifiers.contains(.leftGUI) { symbols += "⌘" }
        symbols += key.symbol
        return symbols
    }
}

private extension Keycode {
    /// How the key is printed on a Mac key cap.
    var symbol: String {
        switch self {
        case .upArrow: "↑"
        case .downArrow: "↓"
        case .leftArrow: "←"
        case .rightArrow: "→"
        case .tab: "⇥"
        case .space: "Space"
        case .equal: "="
        case .minus: "-"
        case .digit3: "3"
        case .a: "A"
        case .c: "C"
        case .h: "H"
        case .n: "N"
        case .r: "R"
        default: "?"
        }
    }
}
