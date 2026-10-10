import CoreGraphics
import Foundation
import SwiftUI
#if os(iOS)
    import UIKit
#endif

/// routes UI input to the active HID backend
struct HIDInput {
    let sendMouse: (MouseReport) -> Void
    let sendKeyboard: (KeyboardReport) -> Void
    let sendConsumer: (ConsumerReport) -> Void
    let sendDigitizer: (DigitizerReport) -> Void
    let updateBattery: (UInt8) -> Void
    let isActive: Bool
    let isConnected: Bool
    let activeError: String?
    let batteryLevel: UInt8

    func tap(_ key: Keycode, modifiers: KeyboardModifiers = []) {
        sendKeyboard(KeyboardReport(modifiers: modifiers, keys: [key]))
        sendKeyboard(.zero)
    }

    func keyDown(_ key: Keycode, modifiers: KeyboardModifiers = []) {
        sendKeyboard(KeyboardReport(modifiers: modifiers, keys: [key]))
    }

    func keyUp() {
        sendKeyboard(.zero)
    }

    func tap(consumer: ConsumerKey) {
        sendConsumer(ConsumerReport(key: consumer))
        sendConsumer(.zero)
    }

    func toggleVirtualKeyboard() {
        tap(consumer: .eject)
    }

    @MainActor
    func click(_ button: MouseButtons) {
        sendMouse(MouseReport(buttons: button))
        let sender = sendMouse
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 25_000_000)
            sender(.zero)
        }
    }

    func move(dx: Int8, dy: Int8, buttons: MouseButtons = []) {
        sendMouse(MouseReport(buttons: buttons, dX: dx, dY: dy))
    }

    func scroll(_ wheel: Int8) {
        sendMouse(MouseReport(wheel: wheel))
        sendMouse(.zero)
    }

    func type(_ character: Character) {
        guard let (key, mods) = mapASCII(character) else { return }
        sendKeyboard(KeyboardReport(modifiers: mods, keys: [key]))
        sendKeyboard(.zero)
    }

    /// down + up reports for one character (empty if unmappable); paced by the caller
    static func keyReports(for character: Character, adding modifiers: KeyboardModifiers = []) -> [KeyboardReport] {
        guard let (key, mods) = mapASCII(character) else { return [] }
        return [KeyboardReport(modifiers: mods.union(modifiers), keys: [key]), .zero]
    }

    static func keyReports(for key: Keycode, modifiers: KeyboardModifiers = []) -> [KeyboardReport] {
        [KeyboardReport(modifiers: modifiers, keys: [key]), .zero]
    }

    @MainActor
    func typeWord(_ text: String) async {
        for character in text {
            type(character)
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    static func clamp(_ value: CGFloat) -> Int8 {
        Int8(max(-127, min(127, Int(value))))
    }
}

extension HIDInput {
    #if os(macOS)
        @MainActor
        static func make(lowEnergy: HIDPeripheral, central: HIDCentral, classic: HIDClassicDevice, classicMode: Bool) -> HIDInput {
            guard classicMode else { return _lowEnergy(lowEnergy, central) }
            return HIDInput(
                sendMouse: { classic.sendMouse($0) },
                sendKeyboard: { classic.sendKeyboard($0) },
                sendConsumer: { classic.sendConsumer($0) },
                sendDigitizer: { classic.sendDigitizer($0) },
                updateBattery: { classic.updateBatteryLevel($0) },
                isActive: classic.isSDPPublished,
                isConnected: classic.connectedAddress != nil,
                activeError: classic.lastError,
                batteryLevel: classic.batteryLevel
            )
        }
    #else
        @MainActor
        static func make(lowEnergy: HIDPeripheral, central: HIDCentral) -> HIDInput {
            _lowEnergy(lowEnergy, central)
        }
    #endif

    static var unavailable: HIDInput {
        HIDInput(
            sendMouse: { _ in }, sendKeyboard: { _ in }, sendConsumer: { _ in }, sendDigitizer: { _ in }, updateBattery: { _ in },
            isActive: false, isConnected: false, activeError: nil, batteryLevel: 0
        )
    }

    @MainActor
    private static func _lowEnergy(_ lowEnergy: HIDPeripheral, _ central: HIDCentral) -> HIDInput {
        HIDInput(
            sendMouse: { lowEnergy.sendMouse($0) },
            sendKeyboard: { lowEnergy.sendKeyboard($0) },
            sendConsumer: { lowEnergy.sendConsumer($0) },
            sendDigitizer: { lowEnergy.sendDigitizer($0) },
            updateBattery: { lowEnergy.updateBatteryLevel($0) },
            isActive: lowEnergy.isHIDServiceAdded,
            isConnected: lowEnergy.connectedCentrals.contains { !lowEnergy.inactiveCentrals.contains($0) } || !central.connected.isEmpty,
            activeError: lowEnergy.lastError ?? central.lastError,
            batteryLevel: lowEnergy.batteryLevel
        )
    }
}

private struct HIDInputKey: EnvironmentKey {
    static var defaultValue: HIDInput { .unavailable }
}

extension EnvironmentValues {
    var hid: HIDInput {
        get { self[HIDInputKey.self] }
        set { self[HIDInputKey.self] = newValue }
    }
}

/// Haptic feedback, modelled on the MacBook trackpad.
///
/// Trackpad clicks use `.rigid` — Apple's description of that style is "crisp,
/// rigid", the closest match to the firm detent of a Force Touch click. Scrolling
/// uses the selection generator, whose rapid tick is what gives the MacBook
/// trackpad its distinctive texture.
///
/// Generators are cached and pre-warmed: the Taptic Engine takes a few
/// milliseconds to spin up, and an unprewarmed first tap is noticeably laggy.
enum Haptics {
    enum Source {
        case trackpad
        case keyboard
    }

    #if os(iOS)
        @MainActor private static var impact: UIImpactFeedbackGenerator?
        @MainActor private static var selection: UISelectionFeedbackGenerator?
        @MainActor private static var lastScrollTick: CFTimeInterval = 0
        /// Ceiling of ~25 ticks/second, so a fast flick stays crisp instead of buzzing.
        private static let scrollTickInterval: CFTimeInterval = 0.04
    #endif

    /// A discrete press: a click, a key, a gesture.
    @MainActor
    static func tap(from source: Source = .trackpad) {
        #if os(iOS)
            guard isEnabled(source) else { return }
            let generator = impactGenerator()
            generator.impactOccurred()
            generator.prepare()
        #endif
    }

    /// A scroll detent. Rate-limited, so callers may fire it per wheel step.
    @MainActor
    static func scrollTick() {
        #if os(iOS)
            let defaults = UserDefaults.standard
            guard defaults.bool(forKey: AppSettings.hapticsEnabledKey),
                  defaults.bool(forKey: AppSettings.hapticsTrackpadKey),
                  defaults.bool(forKey: AppSettings.hapticsScrollKey)
            else { return }
            let now = CACurrentMediaTime()
            guard now - lastScrollTick >= scrollTickInterval else { return }
            lastScrollTick = now
            let generator = selectionGenerator()
            generator.selectionChanged()
            generator.prepare()
        #endif
    }

    /// Spin the engine up ahead of an interaction so the first tap lands on time.
    @MainActor
    static func prepare() {
        #if os(iOS)
            guard UserDefaults.standard.bool(forKey: AppSettings.hapticsEnabledKey) else { return }
            _ = impactGenerator()
            _ = selectionGenerator()
        #endif
    }

    #if os(iOS)
        @MainActor
        private static func isEnabled(_ source: Source) -> Bool {
            let defaults = UserDefaults.standard
            guard defaults.bool(forKey: AppSettings.hapticsEnabledKey) else { return false }
            switch source {
            case .trackpad: return defaults.bool(forKey: AppSettings.hapticsTrackpadKey)
            case .keyboard: return defaults.bool(forKey: AppSettings.hapticsKeyboardKey)
            }
        }

        @MainActor
        private static func impactGenerator() -> UIImpactFeedbackGenerator {
            if let impact {
                return impact
            }
            let generator = UIImpactFeedbackGenerator(style: .rigid)
            generator.prepare()
            impact = generator
            return generator
        }

        @MainActor
        private static func selectionGenerator() -> UISelectionFeedbackGenerator {
            if let selection {
                return selection
            }
            let generator = UISelectionFeedbackGenerator()
            generator.prepare()
            selection = generator
            return generator
        }

    #endif
}

/// US-layout ASCII to keycode/modifier mapping
private func mapASCII(_ character: Character) -> (Keycode, KeyboardModifiers)? {
    if let a = character.asciiValue {
        if a >= 0x61, a <= 0x7A, let key = Keycode(rawValue: 0x04 + (a - 0x61)) { return (key, []) } // a..z
        if a >= 0x41, a <= 0x5A, let key = Keycode(rawValue: 0x04 + (a - 0x41)) { return (key, .leftShift) } // A..Z
    }
    return _symbolKeys[character]
}

private let _shift: KeyboardModifiers = .leftShift
private let _symbolKeys: [Character: (Keycode, KeyboardModifiers)] = [
    "1": (.digit1, []), "2": (.digit2, []), "3": (.digit3, []), "4": (.digit4, []), "5": (.digit5, []),
    "6": (.digit6, []), "7": (.digit7, []), "8": (.digit8, []), "9": (.digit9, []), "0": (.digit0, []),
    "!": (.digit1, _shift), "@": (.digit2, _shift), "#": (.digit3, _shift), "$": (.digit4, _shift), "%": (.digit5, _shift),
    "^": (.digit6, _shift), "&": (.digit7, _shift), "*": (.digit8, _shift), "(": (.digit9, _shift), ")": (.digit0, _shift),
    " ": (.space, []), "\n": (.return, []), "\r": (.return, []), "\t": (.tab, []),
    "-": (.minus, []), "_": (.minus, _shift), "=": (.equal, []), "+": (.equal, _shift),
    "[": (.leftBracket, []), "{": (.leftBracket, _shift), "]": (.rightBracket, []), "}": (.rightBracket, _shift),
    "\\": (.backslash, []), "|": (.backslash, _shift), ";": (.semicolon, []), ":": (.semicolon, _shift),
    "'": (.quote, []), "\"": (.quote, _shift), "`": (.grave, []), "~": (.grave, _shift),
    ",": (.comma, []), "<": (.comma, _shift), ".": (.period, []), ">": (.period, _shift),
    "/": (.slash, []), "?": (.slash, _shift)
]
