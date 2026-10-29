import CoreBluetooth
import SwiftUI

struct SetupView: View {
    @EnvironmentObject private var lowEnergy: HIDPeripheral
    @EnvironmentObject private var names: DeviceNameStore
    @AppStorage(AppSettings.developerModeKey) private var developerMode = false
    @AppStorage(AppSettings.advertisedNameKey) private var advertisedName = L10n.Bluetooth.advertisedName
    @State private var selectedInfo: DeviceEntry?
    @State private var pendingRemoval: DeviceEntry?
    @State private var showRemoveConfirm = false

    @Environment(\.hid) private var hid

    var body: some View {
        NavigationView {
            form.navigationTitle(L10n.App.title)
        }
        .navigationViewStyle(.stack)
    }

    private var form: some View {
        Form {
            guideSection
            connectionSection
            if !lowEnergy.connectedCentrals.isEmpty {
                connectedDevicesSection
            }
            statusSection
            if let lastError = hid.activeError {
                Section(header: Text(L10n.Section.lastError)) {
                    Text(verbatim: lastError).foregroundColor(.red).font(.caption)
                }
            }
        }
        .sheet(item: $selectedInfo) { DeviceInfoView(entry: $0) }
        .confirmationDialog(
            L10n.Device.removeConfirmTitle,
            isPresented: $showRemoveConfirm,
            titleVisibility: .visible,
            presenting: pendingRemoval
        ) { entry in
            Button(L10n.Device.remove, role: .destructive) { lowEnergy.removeCentral(entry.id) }
            Button(L10n.Action.notNow, role: .cancel) {}
        } message: { _ in
            Text(L10n.Device.removeConfirmMessage)
        }
    }

    private var guideSection: some View {
        Section(header: Text(L10n.Setup.help)) {
            NavigationLink { GuideView() } label: {
                Label(L10n.Setup.lowEnergyGuide, systemImage: "questionmark.circle")
            }
            Link(destination: AppSettings.instructionsURL) {
                Label(L10n.Setup.videoInstructions, systemImage: "play.circle")
            }
        }
    }

    private var statusSection: some View {
        Section(header: Text(L10n.Section.status)) {
            advertisedNameRow
            row(L10n.Status.bluetooth, Text(lowEnergy.state.localizedLabel))
            row(L10n.Status.advertising, Text(lowEnergy.isAdvertising ? L10n.Value.yes : L10n.Value.no))
            if developerMode {
                row(L10n.Status.hidService, Text(lowEnergy.isHIDServiceAdded ? L10n.Status.hidServiceAdded : L10n.Value.none))
                row(L10n.Status.subscribedCentrals, Text(lowEnergy.subscribedCentrals.count, format: .number))
                row(L10n.Status.hostLEDs, Text(verbatim: lowEnergy.keyboardLEDs.localizedLabel))
            }
        }
    }

    private var advertisedNameRow: some View {
        NavigationLink {
            NameEditView(
                title: L10n.Setup.advertisedName,
                footer: L10n.Setup.advertisedNameHint,
                maxLength: AppSettings.maxAdvertisedNameLength,
                name: $advertisedName,
                onCommit: _applyAdvertisedName
            )
        } label: {
            HStack {
                Text(L10n.Setup.advertisedName)
                Spacer()
                Text(verbatim: advertisedName).foregroundColor(.secondary)
            }
        }
    }

    private func _applyAdvertisedName() {
        if advertisedName.isEmpty {
            advertisedName = L10n.Bluetooth.advertisedName
        }
        lowEnergy.advertiseLocalName = advertisedName
        guard lowEnergy.isAdvertising else { return }
        lowEnergy.stop()
        lowEnergy.start()
    }

    private var connectionSection: some View {
        Section(header: Text(L10n.Section.connection), footer: Text(L10n.Setup.deviceNameLimitation)) {
            if lowEnergy.isAdvertising {
                Button(role: .destructive) { lowEnergy.stop() } label: {
                    Label(L10n.Action.stopAdvertising, systemImage: "stop.circle")
                }
            } else {
                Button { _startAdvertising() } label: {
                    Label(L10n.Action.startAdvertising, systemImage: "antenna.radiowaves.left.and.right")
                }
            }
        }
    }

    private var connectedDevicesSection: some View {
        Section {
            ForEach(_connectedDevices) { connectedDeviceRow($0) }
        } footer: {
            Text(L10n.Setup.activeLegend)
        }
    }

    /// Hosts that connected to us (peripheral role), removed ones included: they stay
    /// linked at the Bluetooth level, so the row is where the user gets them back.
    private var _connectedDevices: [DeviceEntry] {
        lowEnergy.connectedCentrals
            .map { uuid in
                let alias = names.name(for: uuid)
                let subscribed = lowEnergy.subscribedCentrals.keys.contains(uuid)
                return DeviceEntry(
                    id: uuid,
                    name: alias ?? "",
                    isNamed: alias != nil,
                    isSubscribed: subscribed,
                    isActive: subscribed && lowEnergy.activeCentral == uuid,
                    isMuted: lowEnergy.inactiveCentrals.contains(uuid),
                    isRemoved: lowEnergy.isBlocked(uuid)
                )
            }
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }

    private func _startAdvertising() {
        if lowEnergy.state == .poweredOn {
            lowEnergy.start()
            return
        }
        lowEnergy.promptPowerAlert()
    }

    private func connectedDeviceRow(_ entry: DeviceEntry) -> some View {
        ConnectedDeviceRow(
            entry: entry,
            onToggle: { lowEnergy.toggleActive(entry.id) },
            onInfo: { selectedInfo = entry },
            onRemove: {
                pendingRemoval = entry
                showRemoveConfirm = true
            },
            onUse: { lowEnergy.makeActive(entry.id) },
            onRestore: { lowEnergy.restoreCentral(entry.id) }
        )
    }

    private func row(_ title: LocalizedStringKey, _ value: Text) -> some View {
        HStack {
            Text(title)
            Spacer()
            value.foregroundColor(.secondary)
        }
    }
}

private extension CBManagerState {
    var localizedLabel: LocalizedStringKey {
        switch self {
        case .unknown: return L10n.BluetoothState.unknown
        case .resetting: return L10n.BluetoothState.resetting
        case .unsupported: return L10n.BluetoothState.unsupported
        case .unauthorized: return L10n.BluetoothState.unauthorized
        case .poweredOff: return L10n.BluetoothState.poweredOff
        case .poweredOn: return L10n.BluetoothState.poweredOn
        @unknown default: return L10n.BluetoothState.unavailable
        }
    }
}

private extension KeyboardLEDs {
    var localizedLabel: String {
        var parts: [String] = []
        if contains(.numLock) {
            parts.append(L10n.KeyboardLED.numLock)
        }
        if contains(.capsLock) {
            parts.append(L10n.KeyboardLED.capsLock)
        }
        if contains(.scrollLock) {
            parts.append(L10n.KeyboardLED.scrollLock)
        }
        return parts.isEmpty ? L10n.Value.noneString : ListFormatter.localizedString(byJoining: parts)
    }
}

#if DEBUG
    #Preview {
        SetupView()
            .environmentObject(HIDPeripheral())
            .environmentObject(DeviceNameStore())
    }
#endif
