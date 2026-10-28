import SwiftUI
import UIKit

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
        usesPureBlackSurface ? .black : Color(uiColor: .systemBackground)
    }

    var dockFill: Color {
        usesPureBlackSurface ? Color(white: 0.04) : Color.secondary.opacity(0.12)
    }
}

extension EnvironmentValues {
    @Entry var appTheme: AppTheme = .system
}
