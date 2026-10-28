import Foundation

/// One place that can end every piece of input state the app is holding.
///
/// The keyboard page and the trackpad page each register a release closure for as
/// long as their view is in the hierarchy. `releaseAll(using:)` runs every
/// registered closure in registration order, then sends the clearing reports:
/// a zero keyboard report after all keyboard state is gone and a zero mouse report
/// after all pointer state is gone.
///
/// Every path that can interrupt input goes through here — page switch, scene
/// background, disconnection, HID teardown — and each registered closure is written
/// to be safe to call repeatedly. A second release while nothing is held changes no
/// state and therefore cannot produce a second button transition.
@MainActor
final class InputReleaseCoordinator: ObservableObject {
    struct Token: Hashable {
        let id: UUID
    }

    private struct Registration {
        let token: Token
        let release: @MainActor () -> Void
    }

    private var registrations: [Registration] = []
    /// A release closure must never re-enter the coordinator: the views' own
    /// disappearance paths also call `releaseAll`, and a re-entrant call would run
    /// the same closures while their state is half cleared.
    private var isReleasing = false

    @discardableResult
    func register(_ release: @escaping @MainActor () -> Void) -> Token {
        let token = Token(id: UUID())
        registrations.append(Registration(token: token, release: release))
        return token
    }

    func unregister(_ token: Token) {
        registrations.removeAll { $0.token == token }
    }

    /// Releases everything and clears the host. The keyboard zero goes last, after
    /// the closures have cleared held keys and modifiers, so a release can never
    /// leave a key latched behind it.
    func releaseAll(using hid: HIDInput) {
        guard !isReleasing else { return }
        isReleasing = true
        defer { isReleasing = false }

        for registration in registrations {
            registration.release()
        }
        hid.sendKeyboard(.zero)
        hid.sendMouse(.zero)
    }
}
