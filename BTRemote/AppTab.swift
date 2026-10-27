import SwiftUI

enum AppTab: Hashable, CaseIterable {
    case setup
    case remote
    case settings

    var title: LocalizedStringKey {
        switch self {
        case .setup: L10n.Tab.setup
        case .remote: L10n.Tab.remote
        case .settings: L10n.Tab.settings
        }
    }

    var icon: String {
        switch self {
        case .setup: "gearshape"
        case .remote: "keyboard"
        case .settings: "slider.horizontal.3"
        }
    }
}
