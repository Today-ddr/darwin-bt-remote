import SwiftUI

enum AppTab: Hashable, CaseIterable {
    case setup
    case input
    case settings

    var title: LocalizedStringKey {
        switch self {
        case .setup: L10n.Tab.setup
        case .input: L10n.Tab.input
        case .settings: L10n.Tab.settings
        }
    }

    var icon: String {
        switch self {
        case .setup: "gearshape"
        case .input: "keyboard"
        case .settings: "slider.horizontal.3"
        }
    }
}
