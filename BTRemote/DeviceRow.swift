import SwiftUI

struct DeviceEntry: Identifiable, Equatable {
    let id: UUID
    let name: String
    let isNamed: Bool
    let isSubscribed: Bool
    /// holds control: the one host that receives input
    let isActive: Bool
    /// muted by the user; suppresses this host's input without handing control to another
    let isMuted: Bool
    /// removed by the user; stays linked, but needs a restore before it can be used again
    let isRemoved: Bool

    var displayName: String {
        if isNamed {
            return name
        }
        return L10n.Device.unknownName
    }
}

struct RowLeadingStatus: View {
    enum Phase { case idle, active }
    let phase: Phase

    var body: some View {
        ZStack {
            switch phase {
            case .idle:
                Color.clear
            case .active:
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundColor(.accentColor)
            }
        }
        .frame(width: 22)
    }
}

/// a host connected to us (peripheral role): the row states its relationship to control
/// and carries the two things the user can do about it, switch and restore
struct ConnectedDeviceRow: View {
    let entry: DeviceEntry
    let onToggle: () -> Void
    let onInfo: () -> Void
    let onRemove: () -> Void
    let onUse: () -> Void
    let onRestore: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // only a subscribed host that has not been removed can be muted by tapping its
            // name; a removed row must not hide a second action behind the same tap
            if entry.isSubscribed, !entry.isRemoved {
                Button(action: onToggle) { label }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text(verbatim: entry.displayName))
                    .accessibilityValue(entry.isMuted ? Text(L10n.Device.inactive) : Text(verbatim: ""))
            } else {
                label
            }
            controlButton
            Button(action: onInfo) {
                Image(systemName: "info.circle").foregroundColor(.accentColor)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(L10n.DeviceInfo.info)

            Button(role: .destructive, action: onRemove) {
                Image(systemName: "trash").foregroundColor(.red)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(L10n.Device.remove)
        }
    }

    /// The trash button is the only way out; this one is the way in, and doubles as the
    /// row's control state. The active host shows a filled icon instead of a button — there
    /// is nothing to switch it to — and a host that cannot be switched to yet shows nothing.
    @ViewBuilder
    private var controlButton: some View {
        if entry.isRemoved {
            Button(action: onRestore) {
                Image(systemName: "arrow.uturn.backward.circle").foregroundColor(.accentColor)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(L10n.Device.restore)
        } else if entry.isSubscribed {
            if entry.isActive {
                Image(systemName: "link.circle.fill").foregroundColor(.green)
                    .accessibilityLabel(L10n.Device.inUse)
            } else {
                Button(action: onUse) {
                    Image(systemName: "link.circle").foregroundColor(.accentColor)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(L10n.Device.use)
            }
        }
    }

    private var label: some View {
        HStack(spacing: 12) {
            RowLeadingStatus(phase: entry.isActive ? .active : .idle)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: entry.displayName).foregroundColor(.primary)
                Text(verbatim: entry.id.uuidString)
                    .font(.caption2).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer()
            if !entry.isSubscribed {
                Text(L10n.Device.notSubscribed).font(.caption).foregroundColor(.secondary)
            }
            if entry.isMuted {
                // the row's own label for a state the control button no longer carries
                Text(L10n.Device.inactive).font(.caption).foregroundColor(.secondary)
            }
            Text(controlLabel).font(.caption).foregroundColor(controlColor)
        }
        .contentShape(Rectangle())
    }

    private var controlLabel: LocalizedStringKey {
        if entry.isRemoved {
            return L10n.Device.removed
        }
        return entry.isActive ? L10n.Device.inUse : L10n.Device.standby
    }

    private var controlColor: Color {
        if entry.isRemoved {
            return .red
        }
        return entry.isActive ? .green : .secondary
    }
}
