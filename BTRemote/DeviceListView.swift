import CoreBluetooth
import SwiftUI

/// Nearby peripherals found by the central side, with connect/disconnect on each row.
///
/// This page only discovers and manages links; it is not a host list and connecting here
/// never opens the input page (that reads the peripheral side's host state alone).
struct DeviceListView: View {
    @EnvironmentObject private var central: HIDCentral
    @State private var selectedInfo: DeviceEntry?

    var body: some View {
        Form {
            scanSection
            devicesSection
            if let lastError = central.lastError {
                Section(header: Text(L10n.Section.lastError)) {
                    Text(verbatim: lastError).foregroundColor(.red).font(.caption)
                }
            }
        }
        .navigationTitle(L10n.Section.devices)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedInfo) { DeviceInfoView(entry: $0) }
        .onAppear { central.startScan() }
        .onDisappear { central.stopScan() }
    }

    private var scanSection: some View {
        Section {
            if central.isScanning {
                Button(role: .destructive) { central.stopScan() } label: {
                    Label(L10n.Action.stopScanning, systemImage: "stop.circle")
                }
            } else {
                Button { central.startScan() } label: {
                    Label(L10n.Action.scanNearbyDevices, systemImage: "magnifyingglass")
                }
            }
        } footer: {
            // a scan that cannot run because the radio is off must say so instead of looking
            // like a scan that simply finds nothing
            if central.state != .poweredOn, central.state != .unknown {
                Text(L10n.Status.bluetooth) + Text(verbatim: " · ") + Text(central.state.localizedLabel)
            }
        }
    }

    private var devicesSection: some View {
        Section {
            ForEach(_devices) { deviceRow($0) }
            if _devices.isEmpty, !central.isScanning {
                Text(L10n.Device.emptyState)
                    .font(.caption).foregroundColor(.secondary)
            }
        } footer: {
            if !_devices.isEmpty {
                Text(L10n.Device.connectedLegend)
            }
        }
    }

    /// Peripherals found by scanning, name-sorted.
    private var _devices: [DeviceEntry] {
        central.discovered
            .map { peripheral in
                DeviceEntry(
                    id: peripheral.id,
                    name: peripheral.name,
                    isNamed: peripheral.isNamed,
                    rssi: peripheral.rssi,
                    advertisedServices: peripheral.advertisedServices,
                    isCentralConnected: central.connected.contains(peripheral.id),
                    isConnecting: central.connecting.contains(peripheral.id),
                    // a scanned peripheral is only a central-role link; none of the host
                    // states describe it, so they stay at their neutral values
                    isSubscribed: false,
                    isActive: false,
                    isMuted: false,
                    isRemoved: false,
                    allowsNameEditing: false
                )
            }
            .sorted { lhs, rhs in
                let order = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
                guard order != .orderedSame else { return lhs.id.uuidString < rhs.id.uuidString }
                return order == .orderedAscending
            }
    }

    private func deviceRow(_ entry: DeviceEntry) -> some View {
        DeviceRow(
            entry: entry,
            accessibilityLabel: _accessibilityLabel(for: entry),
            action: {
                if entry.isConnecting {
                    central.cancelConnection(entry.id)
                } else if entry.isCentralConnected {
                    central.disconnect(entry.id)
                } else {
                    central.connect(entry.id)
                }
            },
            onInfo: { selectedInfo = entry }
        ) {
            if entry.rssi != 0 {
                Text(verbatim: L10n.Device.rssi(entry.rssi))
                    .font(.caption).foregroundColor(.secondary)
            }
        }
    }

    /// The row's tap means connect, disconnect or cancel depending on the link's state, and
    /// the label has to say which one it is.
    private func _accessibilityLabel(for entry: DeviceEntry) -> String {
        if entry.isConnecting {
            return L10n.Device.cancelConnectAccessibilityLabel(entry.displayName)
        }
        if entry.isCentralConnected {
            return L10n.Device.disconnectAccessibilityLabel(entry.displayName)
        }
        return L10n.Device.connectAccessibilityLabel(entry.displayName)
    }
}

#if DEBUG
    #Preview {
        NavigationView {
            DeviceListView()
        }
        .navigationViewStyle(.stack)
        .environmentObject(HIDCentral())
        .environmentObject(DeviceNameStore())
    }
#endif
