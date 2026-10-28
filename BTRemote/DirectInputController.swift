import CoreGraphics
import Foundation
import GameController
import SwiftUI
import UIKit

@MainActor
final class DirectInputController: ObservableObject {
    @Published private(set) var isCapturing = false
    @Published private(set) var lastError: String?
    @Published private(set) var hasInputDevice = false

    private var sendKeyboard: ((KeyboardReport) -> Void)?
    private var sendMouse: ((MouseReport) -> Void)?
    private var pressedKeys: Set<Keycode> = []
    private var pressedMouseButtons: MouseButtons = []
    private var modifiers: KeyboardModifiers = []
    private var observers: [NSObjectProtocol] = []

    // GCMouse deltas are in points; tune on-device
    private static let sensitivity: CGFloat = 1
    private static let scrollSensitivity: CGFloat = 1

    init() {
        refreshDevicePresence()
        observeDevices()
    }

    func start(_ hid: HIDInput) {
        start(sendKeyboard: hid.sendKeyboard, sendMouse: hid.sendMouse)
    }

    func start(
        sendKeyboard: @escaping (KeyboardReport) -> Void,
        sendMouse: @escaping (MouseReport) -> Void
    ) {
        stop()
        guard hasInputDevice else { return }

        self.sendKeyboard = sendKeyboard
        self.sendMouse = sendMouse
        pressedKeys.removeAll()
        pressedMouseButtons = []
        modifiers = []
        lastError = nil

        attachHandlers()
        isCapturing = true
    }

    func stop() {
        detachHandlers()
        if isCapturing {
            sendKeyboard?(.zero)
            sendMouse?(.zero)
        }
        pressedKeys.removeAll()
        pressedMouseButtons = []
        modifiers = []
        sendKeyboard = nil
        sendMouse = nil
        isCapturing = false
    }

    private func attachHandlers() {
        if let keyboard = GCKeyboard.coalesced {
            keyboard.handlerQueue = .main
            keyboard.keyboardInput?.keyChangedHandler = { [weak self] _, _, keyCode, pressed in
                let raw = keyCode.rawValue
                Task { @MainActor in self?.handleKey(raw: raw, pressed: pressed) }
            }
        }
        if let mouse = GCMouse.current {
            mouse.handlerQueue = .main
            let input = mouse.mouseInput
            input?.mouseMovedHandler = { [weak self] _, dx, dy in
                Task { @MainActor in self?.handleMove(dx: dx, dy: dy) }
            }
            input?.leftButton.pressedChangedHandler = { [weak self] _, _, pressed in
                Task { @MainActor in self?.handleButton(.left, pressed) }
            }
            input?.rightButton?.pressedChangedHandler = { [weak self] _, _, pressed in
                Task { @MainActor in self?.handleButton(.right, pressed) }
            }
            input?.middleButton?.pressedChangedHandler = { [weak self] _, _, pressed in
                Task { @MainActor in self?.handleButton(.middle, pressed) }
            }
            input?.scroll.valueChangedHandler = { [weak self] _, _, y in
                Task { @MainActor in self?.handleScroll(y) }
            }
        }
    }

    private func detachHandlers() {
        GCKeyboard.coalesced?.keyboardInput?.keyChangedHandler = nil
        if let input = GCMouse.current?.mouseInput {
            input.mouseMovedHandler = nil
            input.leftButton.pressedChangedHandler = nil
            input.rightButton?.pressedChangedHandler = nil
            input.middleButton?.pressedChangedHandler = nil
            input.scroll.valueChangedHandler = nil
        }
    }

    /// GCKeyCode raw values are HID usage IDs; 0xE0...0xE7 are modifier keys
    private func handleKey(raw: Int, pressed: Bool) {
        if (0xE0 ... 0xE7).contains(raw) {
            let mod = KeyboardModifiers(rawValue: UInt8(1) << UInt8(raw - 0xE0))
            if pressed {
                modifiers.insert(mod)
            } else {
                modifiers.remove(mod)
            }
        } else if let key = Keycode(rawValue: UInt8(truncatingIfNeeded: raw)) {
            if pressed {
                pressedKeys.insert(key)
            } else {
                pressedKeys.remove(key)
            }
        } else {
            return
        }
        if releaseComboHeld {
            stop()
            return
        }
        sendKeyboard?(KeyboardReport(modifiers: modifiers, keys: Array(pressedKeys.prefix(6))))
    }

    private var releaseComboHeld: Bool {
        !modifiers.isDisjoint(with: [.leftCtrl, .rightCtrl]) &&
            !modifiers.isDisjoint(with: [.leftAlt, .rightAlt])
    }

    private func handleMove(dx: Float, dy: Float) {
        let mx = HIDInput.clamp(CGFloat(dx) * Self.sensitivity)
        let my = HIDInput.clamp(CGFloat(-dy) * Self.sensitivity) // GC y is up-positive, HID is down-positive
        guard mx != 0 || my != 0 else { return }
        sendMouse?(MouseReport(buttons: pressedMouseButtons, dX: mx, dY: my))
    }

    private func handleButton(_ button: MouseButtons, _ pressed: Bool) {
        if pressed {
            pressedMouseButtons.insert(button)
        } else {
            pressedMouseButtons.remove(button)
        }
        sendMouse?(MouseReport(buttons: pressedMouseButtons))
    }

    private func handleScroll(_ y: Float) {
        let wheel = HIDInput.clamp(CGFloat(y) * Self.scrollSensitivity)
        guard wheel != 0 else { return }
        sendMouse?(MouseReport(buttons: pressedMouseButtons, wheel: wheel))
        sendMouse?(MouseReport(buttons: pressedMouseButtons))
    }

    private func refreshDevicePresence() {
        hasInputDevice = GCKeyboard.coalesced != nil || GCMouse.current != nil
    }

    private func observeDevices() {
        let names: [Notification.Name] = [
            .GCKeyboardDidConnect, .GCKeyboardDidDisconnect, .GCMouseDidConnect, .GCMouseDidDisconnect
        ]
        for name in names {
            let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.refreshDevicePresence()
                    if self.isCapturing {
                        self.attachHandlers()
                    }
                    if !self.hasInputDevice {
                        self.stop()
                    }
                }
            }
            observers.append(token)
        }
    }
}

/// iPadOS pointer lock hides system pointer so GameController receives raw deltas
struct PointerLockHost: UIViewControllerRepresentable {
    var locked: Bool

    func makeUIViewController(context: Context) -> PointerLockController {
        PointerLockController()
    }

    func updateUIViewController(_ controller: PointerLockController, context: Context) {
        controller.locked = locked
    }
}

final class PointerLockController: UIViewController {
    var locked = false {
        didSet {
            guard locked != oldValue else { return }
            setNeedsUpdateOfPrefersPointerLocked()
        }
    }

    override var prefersPointerLocked: Bool {
        locked
    }
}
