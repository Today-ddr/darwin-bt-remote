import SwiftUI

enum KeyboardStatusKind: Equatable {
    case error
    case connected
    case ready
    case inactive

    var title: LocalizedStringKey {
        switch self {
        case .error: L10n.Keyboard.statusError
        case .connected: L10n.Keyboard.statusConnected
        case .ready: L10n.Keyboard.statusReady
        case .inactive: L10n.Keyboard.statusInactive
        }
    }
}

struct KeyboardStatusSnapshot: Equatable {
    let isActive: Bool
    let isConnected: Bool
    let connectedHostCount: Int
    let errorMessage: String?
    let isCapsLockOn: Bool
    let isShiftActive: Bool

    var kind: KeyboardStatusKind {
        if let errorMessage, !errorMessage.isEmpty {
            return .error
        }
        if isConnected {
            return .connected
        }
        return isActive ? .ready : .inactive
    }

    var connectedCountText: String? {
        guard kind == .connected else { return nil }
        return "\(max(1, connectedHostCount))"
    }

    var modifierGlyph: String? {
        if isCapsLockOn {
            return "⇪"
        }
        return isShiftActive ? "⇧" : nil
    }

    var accessibilityValue: String {
        if kind == .error, let errorMessage {
            return errorMessage
        }
        if kind == .connected {
            return "\(max(1, connectedHostCount))"
        }
        return ""
    }
}

struct KeyboardStatusBadge: View {
    let status: KeyboardStatusSnapshot

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        HStack(spacing: 3) {
            stateMark

            if let count = status.connectedCountText {
                Text(verbatim: count)
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
            }

            if let glyph = status.modifierGlyph {
                Text(verbatim: glyph)
            }
        }
        .font(.system(size: 9, weight: .semibold, design: .rounded))
        .foregroundStyle(.primary)
        .lineLimit(1)
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .frame(width: 38)
        .background(Capsule().fill(appTheme.controlFill))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.kind.title)
        .accessibilityValue(Text(verbatim: status.accessibilityValue))
    }

    @ViewBuilder
    private var stateMark: some View {
        if status.kind == .error {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color.red)
        } else {
            Circle()
                .fill(stateColor)
                .frame(width: 6, height: 6)
        }
    }

    private var stateColor: Color {
        switch status.kind {
        case .error: .red
        case .connected: .green
        case .ready: .orange
        case .inactive: .secondary
        }
    }
}
