import CoreBluetooth
import SwiftUI

/// scan-list device line (central role)
struct DeviceRow<Trailing: View>: View {
    let entry: DeviceEntry
    var accessibilityLabel: String?
    let action: () -> Void
    let onInfo: () -> Void
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack {
            Button(action: action) {
                HStack {
                    RowLeadingStatus(phase: entry.isConnecting ? .connecting : (entry.isCentralConnected ? .active : .idle))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: entry.displayName).foregroundColor(.primary)
                        Text(verbatim: entry.id.uuidString)
                            .font(.caption2).foregroundColor(.secondary).lineLimit(1)
                    }
                    Spacer()
                    trailing()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text(verbatim: accessibilityLabel ?? entry.displayName))

            Button(action: onInfo) {
                Image(systemName: "info.circle").foregroundColor(.accentColor)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(L10n.DeviceInfo.info)
        }
    }
}

struct DeviceEntry: Identifiable, Equatable {
    let id: UUID
    let name: String
    let isNamed: Bool
    let rssi: Int
    let advertisedServices: [CBUUID]
    let companyID: UInt16?
    let txPower: Int?
    let isConnectable: Bool?
    let isHostConnected: Bool
    let isCentralConnected: Bool
    let isConnecting: Bool
    let isSubscribed: Bool
    /// holds control: the one host that receives input
    let isActive: Bool
    /// muted by the user; suppresses this host's input without handing control to another
    let isMuted: Bool
    /// removed by the user; stays linked, but needs a restore before it can be used again
    let isRemoved: Bool

    var isLive: Bool {
        isCentralConnected || (isHostConnected && isActive)
    }

    var manufacturer: String? {
        companyID.flatMap { BluetoothNumbers.company($0) }
    }

    var displayName: String {
        if isNamed { return name }
        return "[\(manufacturer ?? L10n.Device.unknownManufacturer)]"
    }
}

struct RowLeadingStatus: View {
    enum Phase { case idle, connecting, active }
    let phase: Phase

    var body: some View {
        ZStack {
            switch phase {
            case .idle:
                Color.clear
            case .connecting:
                ProgressView()
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
            if entry.isSubscribed {
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
