import CoreGraphics
import Foundation
import SwiftUI
import UIKit

/// routes UI input to the active HID backend
struct HIDInput {
    let sendMouse: (MouseReport) -> Void
    let sendKeyboard: (KeyboardReport) -> Void
    let updateBattery: (UInt8) -> Void
    let isActive: Bool
    let isConnected: Bool
    let activeError: String?
    let batteryLevel: UInt8
    /// The host's Caps Lock LED, as reported in the HID LED output report. It is
    /// the only Caps Lock state the app has: the device that owns the keyboard
    /// decides what Caps Lock means, and the LED is the authority on it.
    let isCapsLockOn: Bool

    func tap(_ key: Keycode, modifiers: KeyboardModifiers = []) {
        sendKeyboard(KeyboardReport(modifiers: modifiers, keys: [key]))
        sendKeyboard(.zero)
    }

    /// A click is a press immediately followed by the matching release, both applied
    /// on the main actor in call order. There is no deferred release that a later
    /// press could race: an older zero can therefore never overwrite a newer press.
    func click(_ button: MouseButtons) {
        sendMouse(MouseReport(buttons: button))
        sendMouse(.zero)
    }

    /// One relative wheel report and nothing else. Relative wheel input needs no
    /// release report, and a zero written immediately after it can be coalesced
    /// with the delta by the transport or the host — which is what made the
    /// right-side buttons look dead.
    func scroll(_ wheel: Int8) {
        guard wheel != 0 else { return }
        sendMouse(MouseReport(wheel: wheel))
    }

    static func clamp(_ value: CGFloat) -> Int8 {
        Int8(max(-127, min(127, Int(value))))
    }
}

extension HIDInput {
    @MainActor
    static func make(lowEnergy: HIDPeripheral) -> HIDInput {
        HIDInput(
            sendMouse: { lowEnergy.sendMouse($0) },
            sendKeyboard: { lowEnergy.sendKeyboard($0) },
            updateBattery: { lowEnergy.updateBatteryLevel($0) },
            isActive: lowEnergy.isHIDServiceAdded,
            isConnected: lowEnergy.connectedCentrals.contains { !lowEnergy.inactiveCentrals.contains($0) },
            activeError: lowEnergy.lastError,
            batteryLevel: lowEnergy.batteryLevel,
            isCapsLockOn: lowEnergy.keyboardLEDs.contains(.capsLock)
        )
    }

    static var unavailable: HIDInput {
        HIDInput(
            sendMouse: { _ in }, sendKeyboard: { _ in }, updateBattery: { _ in },
            isActive: false, isConnected: false, activeError: nil, batteryLevel: 0,
            isCapsLockOn: false
        )
    }
}

extension EnvironmentValues {
    @Entry var hid: HIDInput = .unavailable
}

/// Haptic feedback, modelled on the MacBook trackpad.
///
/// Trackpad clicks use `.rigid` — Apple's description of that style is "crisp,
/// rigid", the closest match to the firm detent of a Force Touch click. Scrolling
/// uses the selection generator, whose rapid tick is what gives the MacBook
/// trackpad its distinctive texture. Both scale with the intensity setting, so a
/// softer setting softens the whole feel rather than one surface.
///
/// Generators are cached and pre-warmed: the Taptic Engine takes a few
/// milliseconds to spin up, and an unprewarmed first tap is noticeably laggy.
/// The impact generator's style is fixed at init, so the cache is tagged with
/// the intensity it was built for and rebuilt when the setting changes.
enum Haptics {
    enum Source {
        case trackpad
        case keyboard
    }

    /// How firm the feedback feels, persisted as `hapticsIntensityKey`.
    enum Intensity: String {
        case light
        case medium
        case strong

        /// `.medium` is the default feel for a Mac-like input surface, and also
        /// the fallback for an absent or unrecognised stored value.
        static func from(_ setting: String?) -> Intensity {
            Intensity(rawValue: setting ?? "") ?? .medium
        }
    }

    @MainActor private static var impact: UIImpactFeedbackGenerator?
    /// The intensity `impact` was created with; `.strong` maps to `.rigid`, so
    /// a stale generator would silently ignore a change to the setting.
    @MainActor private static var impactIntensity: Intensity?
    @MainActor private static var selection: UISelectionFeedbackGenerator?
    @MainActor private static var lastScrollTick: CFTimeInterval = 0
    /// Ceiling of ~25 ticks/second, so a fast flick stays crisp instead of buzzing.
    private static let scrollTickInterval: CFTimeInterval = 0.04

    /// A discrete press: a click, a key, a gesture.
    @MainActor
    static func tap(from source: Source = .trackpad) {
        guard isEnabled(source) else { return }
        let generator = impactGenerator(for: intensity)
        generator.impactOccurred()
        generator.prepare()
    }

    /// A scroll detent. Rate-limited, so callers may fire it per wheel step.
    @MainActor
    static func scrollTick() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: AppSettings.hapticsEnabledKey),
              defaults.bool(forKey: AppSettings.hapticsTrackpadKey),
              defaults.bool(forKey: AppSettings.hapticsScrollKey)
        else { return }
        let now = CACurrentMediaTime()
        guard now - lastScrollTick >= scrollTickInterval else { return }
        lastScrollTick = now
        let level = intensity
        if let damped = scrollImpactIntensity(for: level) {
            // The selection generator has no style to soften, so the lighter
            // levels substitute a damped impact for the bare tick.
            let generator = impactGenerator(for: level)
            generator.impactOccurred(intensity: damped)
            generator.prepare()
        } else {
            let generator = selectionGenerator()
            generator.selectionChanged()
            generator.prepare()
        }
    }

    /// Spin the engine up ahead of an interaction so the first tap lands on time.
    @MainActor
    static func prepare() {
        guard UserDefaults.standard.bool(forKey: AppSettings.hapticsEnabledKey) else { return }
        _ = impactGenerator(for: intensity)
        _ = selectionGenerator()
    }

    @MainActor
    private static func isEnabled(_ source: Source) -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: AppSettings.hapticsEnabledKey) else { return false }
        switch source {
        case .trackpad: return defaults.bool(forKey: AppSettings.hapticsTrackpadKey)
        case .keyboard: return defaults.bool(forKey: AppSettings.hapticsKeyboardKey)
        }
    }

    /// The current intensity, read straight from `UserDefaults` so a change in
    /// Settings takes effect immediately.
    @MainActor
    private static var intensity: Intensity {
        Intensity.from(UserDefaults.standard.string(forKey: AppSettings.hapticsIntensityKey))
    }

    /// Impact style per level: `.rigid` is Apple's "crisp, rigid" description,
    /// the mapping for `.strong`.
    @MainActor
    private static func impactStyle(for level: Intensity) -> UIImpactFeedbackGenerator.FeedbackStyle {
        switch level {
        case .light: .light
        case .medium: .medium
        case .strong: .rigid
        }
    }

    /// Strength of the damped impact that stands in for a scroll tick at the
    /// softer levels. `nil` means "use the selection generator", which is the
    /// original tick and therefore the mapping for `.strong` — the selection
    /// generator has no style or intensity of its own to soften, so the softer
    /// levels substitute a reduced-intensity impact at the same level's style.
    @MainActor
    private static func scrollImpactIntensity(for level: Intensity) -> CGFloat? {
        switch level {
        case .light: 0.25
        case .medium: 0.5
        case .strong: nil
        }
    }

    /// `UIImpactFeedbackGenerator` fixes its style at init, so a cached
    /// generator built for a different level is discarded rather than reused.
    @MainActor
    private static func impactGenerator(for level: Intensity) -> UIImpactFeedbackGenerator {
        if let impact, impactIntensity == level {
            return impact
        }
        let generator = UIImpactFeedbackGenerator(style: impactStyle(for: level))
        generator.prepare()
        impact = generator
        impactIntensity = level
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
}
