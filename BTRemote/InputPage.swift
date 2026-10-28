import SwiftUI

/// The two pages of the input tab. The raw values are persisted, so a stored
/// selection survives a relaunch and a reconnect.
enum InputPage: Int, CaseIterable, Identifiable {
    case keyboard = 0
    case trackpad = 1

    var id: Int {
        rawValue
    }

    var title: LocalizedStringKey {
        switch self {
        case .keyboard: L10n.Input.keyboard
        case .trackpad: L10n.Input.trackpad
        }
    }

    var icon: String {
        switch self {
        case .keyboard: "keyboard"
        case .trackpad: "hand.draw"
        }
    }
}
