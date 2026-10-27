import SwiftUI
#if os(iOS)
    import UIKit
#else
    import AppKit
#endif

enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark
    case oled

    var id: String {
        rawValue
    }

    init(storedValue: String) {
        self = AppTheme(rawValue: storedValue) ?? .system
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark, .oled: .dark
        }
    }

    var usesPureBlackSurface: Bool {
        self == .oled
    }

    var pageBackground: Color {
        usesPureBlackSurface ? .black : .clear
    }

    var controlFill: Color {
        usesPureBlackSurface ? Color(white: 0.08) : Color.secondary.opacity(0.16)
    }

    var opaquePageBackground: Color {
        if usesPureBlackSurface {
            return .black
        }
        #if os(iOS)
            return Color(uiColor: .systemBackground)
        #else
            return Color(nsColor: .windowBackgroundColor)
        #endif
    }

    var dockFill: Color {
        usesPureBlackSurface ? Color(white: 0.04) : Color.secondary.opacity(0.12)
    }
}

extension EnvironmentValues {
    @Entry var appTheme: AppTheme = .system
}
