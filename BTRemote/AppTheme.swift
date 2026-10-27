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

    var title: LocalizedStringKey {
        switch self {
        case .system: L10n.Settings.themeSystem
        case .light: L10n.Settings.themeLight
        case .dark: L10n.Settings.themeDark
        case .oled: L10n.Settings.themeOLED
        }
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

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue: AppTheme = .system
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}
