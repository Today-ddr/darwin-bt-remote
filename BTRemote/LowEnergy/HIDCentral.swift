import Combine
import CoreBluetooth
import Foundation
import os

/// Scanned peripheral as the list sees it, before it is turned into a `DeviceEntry`.
struct DiscoveredPeripheral: Identifiable, Equatable {
    let id: UUID
    var name: String
    var isNamed: Bool
    var rssi: Int
    var advertisedServices: [CBUUID]
}

/// Central-side scanner: looks for nearby peripherals and holds the links it is asked to make.
///
/// It is deliberately separate from `HIDPeripheral`. A peripheral found here is a device this
/// app connects to as a client, not a host that receives input, so nothing here may make the
/// app look connected for typing — `HIDInput.isConnected` keeps reading the peripheral side
/// alone.
///
/// It is also foreground-only: no restore identifier, no background mode, no background
/// permission. The manager is created the first time the user opens the device list rather
/// than at launch, because creating a `CBCentralManager` is what makes iOS ask for Bluetooth
/// access; leaving the foreground stops the scan and ends every link this object owns.
@MainActor
final class HIDCentral: NSObject, ObservableObject {
    @Published private(set) var state: CBManagerState = .unknown
    @Published private(set) var isScanning = false
    /// Peripherals seen since the current scan started.
    @Published private(set) var discovered: [DiscoveredPeripheral] = []
    @Published private(set) var connected: Set<UUID> = []
    @Published private(set) var connecting: Set<UUID> = []
    @Published private(set) var lastError: String?

    private let log = Logger(subsystem: "io.github.jqssun.btremote", category: "HIDCentral")
    private var centralManager: CBCentralManager?
    private var peripheralCache: [UUID: CBPeripheral] = [:]
    /// Links the user cancelled while they were still being made. CoreBluetooth reports the
    /// cancelled attempt through `didFailToConnect`, so this is how that callback tells a
    /// deliberate cancel from a real failure.
    private var cancelledConnections: Set<UUID> = []
    /// A scan the user asked for but the manager cannot run yet. The manager is created on
    /// demand and its state is unknown until the first delegate callback, so without this the
    /// first Scan tap would only bring the manager up and the user would have to tap again.
    private var wantsScan = false
    /// Whether the central side has ever been used. It gates the foreground rebuild, so
    /// launching the app — or coming back to it after only advertising — creates no manager
    /// and triggers no Bluetooth prompt.
    private var hasStarted = false

    /// Brings the manager up. Called by the first scan, never by the app's launch path.
    func start() {
        hasStarted = true
        guard centralManager == nil else { return }
        // The power alert is the peripheral's job to decide, not this page: a scan that cannot
        // run says so in the list instead of interrupting the user with a system dialog.
        centralManager = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionShowPowerAlertKey: false]
        )
    }

    /// Rebuilds the manager after a suspension, and only for a session that had already used
    /// it. It never scans: returning to the foreground is not the user asking for a scan.
    func resume() {
        guard hasStarted else { return }
        start()
    }

    /// Ends everything the central side owns: the scan and every link.
    ///
    /// Cancelling each peripheral asks the peer to drop its link; releasing the manager is what
    /// guarantees this side lets go of it either way, and it is why nothing here can connect
    /// while the app is in the background. The link state is cleared here rather than left for
    /// callbacks that a released manager will not deliver.
    func suspend() {
        stopScan()
        let identifiers = connected.union(connecting)
        for identifier in identifiers {
            guard let peripheral = peripheralCache[identifier] else { continue }
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        centralManager = nil
        peripheralCache.removeAll()
        connected.removeAll()
        connecting.removeAll()
        cancelledConnections.removeAll()
        discovered.removeAll()
        lastError = nil
        state = .unknown
        _trace("suspend: \(identifiers.count) link(s) cancelled")
    }

    func startScan() {
        wantsScan = true
        // The manager is created on demand, so the first scan has to bring it up itself:
        // `_startScanIfPossible` can only wait for a manager that already exists.
        start()
        _startScanIfPossible()
    }

    func stopScan() {
        wantsScan = false
        centralManager?.stopScan()
        isScanning = false
        _trace("scan stopped")
    }

    func connect(_ identifier: UUID) {
        guard let centralManager, centralManager.state == .poweredOn else {
            // nothing can be connected to until the radio is back; the list shows the state
            start()
            return
        }
        // one request per peripheral: a second tap on a row that is already linked or still
        // connecting must not queue another link
        guard !connected.contains(identifier), !connecting.contains(identifier) else { return }
        let peripheral = peripheralCache[identifier]
            ?? centralManager.retrievePeripherals(withIdentifiers: [identifier]).first
        guard let peripheral else {
            lastError = L10n.Device.unavailable
            return
        }
        peripheralCache[identifier] = peripheral
        lastError = nil
        cancelledConnections.remove(identifier)
        connecting.insert(identifier)
        centralManager.connect(peripheral, options: nil)
        _trace("connect requested: \(identifier)")
    }

    func disconnect(_ identifier: UUID) {
        guard let centralManager, let peripheral = peripheralCache[identifier] else { return }
        centralManager.cancelPeripheralConnection(peripheral)
    }

    /// Gives up on a link that is still being made. A connecting peripheral is not in
    /// `connected`, and cancelling it is what tells CoreBluetooth the user changed their mind.
    func cancelConnection(_ identifier: UUID) {
        guard connecting.contains(identifier) else { return }
        guard let centralManager, let peripheral = peripheralCache[identifier] else {
            connecting.remove(identifier)
            return
        }
        cancelledConnections.insert(identifier)
        centralManager.cancelPeripheralConnection(peripheral)
        _trace("connect cancelled: \(identifier)")
    }

    /// Starts the scan the user asked for, once there is a manager that can run it. The
    /// delegate callback that reports a powered-on radio comes back here, which is what makes
    /// the first Scan tap work without a second one.
    private func _startScanIfPossible() {
        guard wantsScan,
              !isScanning,
              let centralManager,
              centralManager.state == .poweredOn
        else { return }
        discovered.removeAll()
        lastError = nil
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        isScanning = true
        _trace("scan started")
    }

    private func _upsert(peripheral: CBPeripheral, advertisementData: [String: Any], rssi: Int) {
        let resolvedName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let entry = DiscoveredPeripheral(
            id: peripheral.identifier,
            name: resolvedName ?? L10n.Device.unknownName,
            isNamed: resolvedName != nil,
            rssi: rssi,
            advertisedServices: services
        )
        if let index = discovered.firstIndex(where: { $0.id == entry.id }) {
            let existing = discovered[index]
            // a later advertisement can be missing what an earlier one carried; keep both
            discovered[index] = DiscoveredPeripheral(
                id: entry.id,
                name: entry.isNamed ? entry.name : existing.name,
                isNamed: existing.isNamed || entry.isNamed,
                rssi: rssi == 0 ? existing.rssi : rssi,
                advertisedServices: services.isEmpty ? existing.advertisedServices : services
            )
        } else {
            discovered.append(entry)
        }
    }

    private func _trace(_ message: @autoclosure () -> String) {
        guard UserDefaults.standard.bool(forKey: AppSettings.developerModeKey) else { return }
        // Logger takes its message as an escaping autoclosure, so the non-escaping parameter
        // has to be evaluated first; interpolating it directly is a SILGen error.
        let text = message()
        log.info("\(text, privacy: .public)")
    }
}

extension HIDCentral: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central === centralManager else { return }
        state = central.state
        _trace("central state -> \(central.state.rawValue)")
        guard central.state == .poweredOn else {
            // the radio going away takes the links with it; the manager stays so it can
            // report the radio coming back, and a pending scan waits for that
            isScanning = false
            connected.removeAll()
            connecting.removeAll()
            cancelledConnections.removeAll()
            return
        }
        _startScanIfPossible()
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard central === centralManager else { return }
        peripheralCache[peripheral.identifier] = peripheral
        _upsert(peripheral: peripheral, advertisementData: advertisementData, rssi: RSSI.intValue)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard central === centralManager else { return }
        connecting.remove(peripheral.identifier)
        connected.insert(peripheral.identifier)
        peripheralCache[peripheral.identifier] = peripheral
        lastError = nil
        _trace("connected: \(peripheral.identifier)")
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        guard central === centralManager else { return }
        connecting.remove(peripheral.identifier)
        connected.remove(peripheral.identifier)
        if let error {
            lastError = error.localizedDescription
            log.error("disconnected with error: \(error.localizedDescription, privacy: .public)")
        } else {
            _trace("disconnected: \(peripheral.identifier)")
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        guard central === centralManager else { return }
        connecting.remove(peripheral.identifier)
        guard cancelledConnections.remove(peripheral.identifier) == nil else {
            _trace("connect cancelled: \(peripheral.identifier)")
            return
        }
        lastError = error?.localizedDescription ?? L10n.Device.unavailable
        log.error("failed to connect: \(peripheral.identifier)")
    }
}
