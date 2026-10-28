import Foundation

/// Everything the on-screen keyboard holds: the keys and modifier keys currently
/// down, and the Caps Lock latch.
///
/// Kept apart from the view so the press/release transitions and the report they
/// produce are plain logic: the view forwards touch callbacks and sends whatever
/// `report` returns, and the tests exercise the same transitions without a view.
struct KeyboardInputState: Equatable {
    private(set) var keys = KeyPressTracker<Keycode>()
    private(set) var modifiers = KeyPressTracker<KeyboardModifiers>()
    private(set) var isCapsLockOn = false

    var isEmpty: Bool {
        keys.isEmpty && modifiers.isEmpty
    }

    /// The modifier byte for a report: every held modifier key unioned together.
    var heldModifiers: KeyboardModifiers {
        modifiers.heldKeys.reduce(into: KeyboardModifiers()) { $0.formUnion($1) }
    }

    var isShiftActive: Bool {
        heldModifiers.contains(.leftShift) || heldModifiers.contains(.rightShift) || isCapsLockOn
    }

    /// Returns true on the first finger on the key.
    @discardableResult
    mutating func pressKey(_ key: Keycode) -> Bool {
        keys.press(key)
    }

    /// Returns true when the last finger has left the key.
    @discardableResult
    mutating func releaseKey(_ key: Keycode) -> Bool {
        keys.release(key)
    }

    /// Returns true on the first finger on the modifier key.
    @discardableResult
    mutating func pressModifier(_ mod: KeyboardModifiers) -> Bool {
        modifiers.press(mod)
    }

    /// Returns true when the last finger has left the modifier key.
    @discardableResult
    mutating func releaseModifier(_ mod: KeyboardModifiers) -> Bool {
        modifiers.release(mod)
    }

    /// Caps Lock is a latch, not a held key: a tap flips it and no release follows.
    mutating func toggleCapsLock() {
        isCapsLockOn.toggle()
    }

    /// Clears every held key and modifier. Returns true when there was host-visible
    /// state to clear, so a redundant call sends no second release.
    @discardableResult
    mutating func releaseEverything() -> Bool {
        let hadState = !isEmpty
        keys.removeAll()
        modifiers.removeAll()
        return hadState
    }

    /// The report for the state as it stands.
    var report: KeyboardReport {
        KeyboardReport(
            modifiers: effectiveModifiers,
            keys: keys.heldKeys.sorted { $0.rawValue < $1.rawValue }
        )
    }

    /// The current report with one more key inserted, used for the Caps Lock tap.
    /// It carries the held modifiers as they are, not the synthetic Shift below:
    /// the tap reports the Caps Lock key itself, and the held keys follow in a
    /// second report.
    func report(adding key: Keycode) -> KeyboardReport {
        var held = keys.heldKeys
        held.insert(key)
        return KeyboardReport(
            modifiers: heldModifiers,
            keys: held.sorted { $0.rawValue < $1.rawValue }
        )
    }

    /// Caps Lock folds into the report as a Shift over held letters only, which is
    /// what the caps show and what makes the host type the uppercase character.
    private var effectiveModifiers: KeyboardModifiers {
        var mods = heldModifiers
        if isCapsLockOn, keys.heldKeys.contains(where: isLetter) {
            mods.insert(.leftShift)
        }
        return mods
    }

    private func isLetter(_ key: Keycode) -> Bool {
        switch key {
        case .a, .b, .c, .d, .e, .f, .g, .h, .i, .j, .k, .l, .m,
             .n, .o, .p, .q, .r, .s, .t, .u, .v, .w, .x, .y, .z:
            true
        default:
            false
        }
    }
}
