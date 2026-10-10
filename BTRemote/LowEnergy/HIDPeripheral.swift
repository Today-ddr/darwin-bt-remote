import Combine
import CoreBluetooth
import os
import SwiftUI

/// HID-over-GATT peripheral engine
@MainActor
final class HIDPeripheral: NSObject, ObservableObject {
    @Published private(set) var state: CBManagerState = .unknown
    @Published private(set) var isAdvertising = false
    @Published private(set) var isHIDServiceAdded = false
    /// central identifier: the set of characteristic UUIDs it is currently subscribed to
    @Published private(set) var subscribedCentrals: [UUID: Set<CBUUID>] = [:]
    /// broadcasts skip inactive hosts
    @Published private(set) var inactiveCentrals: Set<UUID> = []
    @Published private(set) var connectedCentrals: Set<UUID> = []
    /// the one host that currently receives input. Control is sticky: a host keeps it while
    /// it is away, so the host that reconnects can never take it from one that holds it.
    @Published private(set) var activeCentral: UUID?
    @Published private(set) var keyboardLEDs: KeyboardLEDs = []
    @Published private(set) var lastError: String?
    @Published private(set) var batteryLevel: UInt8 = 100

    private var centralObjects: [UUID: CBCentral] = [:]
    /// hosts the user removed from the list; they stay linked at the Bluetooth level
    /// but receive nothing until the user restores them.
    private var blockedCentrals: Set<UUID> = []

    var advertiseLocalName: String = UserDefaults.standard.string(forKey: AppSettings.advertisedNameKey) ?? L10n.Bluetooth.advertisedName

    private let log = Logger(subsystem: "io.github.jqssun.btremote", category: "HIDPeripheral")
    private var pManager: CBPeripheralManager?
    private var batteryServiceObj: CBMutableService?
    private var deviceInfoServiceObj: CBMutableService?
    private var hidServiceObj: CBMutableService?
    private var isHIDServiceAllowed = false
    private var isReadyToSendNotification = true

    private var charsByReportID: [UInt8: CBMutableCharacteristic] = [:]
    private var bootMouseInputChar: CBMutableCharacteristic?
    private var bootKeyboardInputChar: CBMutableCharacteristic?
    private var bootKeyboardOutputChar: CBMutableCharacteristic?
    private var batteryLevelChar: CBMutableCharacteristic?
    private var serviceChangedObj: CBMutableService?
    private var serviceChangedArmed = false
    private static let serviceChangedGrace: UInt64 = 2_000_000_000

    /// last-sent payloads for reads and new subscriptions
    private var cachedReports: [UInt8: Data] = [
        ReportID.mouse.rawValue: MouseReport.zero.data,
        ReportID.keyboard.rawValue: KeyboardReport.zero.data,
        ReportID.systemControl.rawValue: SystemControlReport.zero.data,
        ReportID.consumerControl.rawValue: ConsumerReport.zero.data,
        ReportID.digitizer.rawValue: DigitizerReport.zero.data
    ]

    /// One parked payload per report ID. A single shared slot let any later report evict a
    /// parked one, so a key-up waiting on the send queue was silently replaced by a mouse
    /// move or a battery update and never reached the host — which then repeated the key
    /// forever because it still believed the key was held.
    ///
    /// Each entry also remembers the host it was addressed to. Only one host receives input
    /// at a time, so anything still queued at a switch belongs to the host that just lost
    /// control and is dropped rather than replayed on the new one; the report of the new
    /// active host that could not be sent is parked on its own turn.
    private var pendingBroadcasts: [UInt8: (data: Data, char: CBMutableCharacteristic, target: UUID?)] = [:]

    func start() {
        isHIDServiceAllowed = true
        if pManager == nil {
            pManager = CBPeripheralManager(
                delegate: self,
                queue: nil,
                options: [CBPeripheralManagerOptionShowPowerAlertKey: true]
            )
        } else if state == .poweredOn {
            if isHIDServiceAdded {
                startAdvertisingNow()
            } else {
                installServices()
            }
        }
    }

    func stop() {
        isHIDServiceAllowed = false
        pManager?.stopAdvertising()
        isAdvertising = false
    }

    func promptPowerAlert() {
        guard state != .poweredOn else { return }
        _resetForRestart()
        start()
    }

    private func _resetForRestart() {
        pManager?.stopAdvertising()
        pManager = nil
        isAdvertising = false
        isHIDServiceAdded = false
        isReadyToSendNotification = true
        pendingBroadcasts.removeAll()
        batteryServiceObj = nil
        deviceInfoServiceObj = nil
        hidServiceObj = nil
        serviceChangedObj = nil
        serviceChangedArmed = false
        batteryLevelChar = nil
        bootMouseInputChar = nil
        bootKeyboardInputChar = nil
        bootKeyboardOutputChar = nil
        charsByReportID.removeAll()
        subscribedCentrals.removeAll()
        inactiveCentrals.removeAll()
        connectedCentrals.removeAll()
        centralObjects.removeAll()
        blockedCentrals.removeAll()
        activeCentral = nil
    }

    func sendMouse(_ report: MouseReport) {
        broadcast(report.data, reportID: .mouse)
    }

    func sendDigitizer(_ report: DigitizerReport) {
        broadcast(report.data, reportID: .digitizer)
    }

    func sendKeyboard(_ report: KeyboardReport) {
        broadcast(report.data, reportID: .keyboard)
        // boot mode hosts read this characteristic instead
        bootKeyboardInputChar.map { _ = updateValue(report.data, for: $0, reportID: ReportID.keyboard.rawValue) }
    }

    func sendConsumer(_ report: ConsumerReport) {
        broadcast(report.data, reportID: .consumerControl)
    }

    func sendSystemControl(_ report: SystemControlReport) {
        broadcast(report.data, reportID: .systemControl)
    }

    func toggleActive(_ uuid: UUID) {
        if inactiveCentrals.contains(uuid) {
            inactiveCentrals.remove(uuid)
        } else {
            inactiveCentrals.insert(uuid)
        }
    }

    /// Stop sending input to a host until the user restores it.
    ///
    /// CoreBluetooth exposes no way for a peripheral to drop a single central —
    /// `CBPeripheralManager` has no counterpart to `cancelPeripheralConnection`,
    /// and removing the service does not notify the peer (it only makes this side
    /// lose track of its subscribers). So the link itself survives and the host stays
    /// in the connected list, marked as removed. There it receives nothing until the
    /// user restores it: the block outlives unsubscribes and reconnects, so a host
    /// that comes back on its own does not get a second chance at the input.
    func removeCentral(_ uuid: UUID) {
        // release before the host is cut off: a key-up sent afterwards goes nowhere, and
        // the host would be left holding whatever was down when control was taken away
        let wasActive = activeCentral == uuid
        if wasActive {
            _releaseHeldKeys()
            activeCentral = nil
        }
        blockedCentrals.insert(uuid)
        inactiveCentrals.remove(uuid)
        objectWillChange.send()
    }

    func isBlocked(_ uuid: UUID) -> Bool {
        blockedCentrals.contains(uuid)
    }

    /// Undo `removeCentral`. A host that is still subscribed is ready to be switched to;
    /// one that is not is eligible to claim control when it next subscribes, provided
    /// nothing holds it by then (see the claim in `didSubscribeTo`).
    func restoreCentral(_ uuid: UUID) {
        blockedCentrals.remove(uuid)
        objectWillChange.send()
    }

    /// Make a subscribed, unblocked host the one that receives input, replacing whatever
    /// held control — no reconnecting needed, the hosts stay linked throughout.
    ///
    /// Keys that are still down are released before the input is rerouted, so the host
    /// losing control is not left with a latched key.
    func makeActive(_ uuid: UUID) {
        guard subscribedCentrals[uuid] != nil,
              !blockedCentrals.contains(uuid),
              activeCentral != uuid
        else { return }
        // the host losing control is told that nothing is held any more, and the new one
        // starts from the same quiet baseline rather than whatever it last knew
        _releaseHeldKeys()
        activeCentral = uuid
        _releaseHeldKeys()
        _trace("active host: \(uuid)")
    }

    /// Releases everything a host could be holding. One zeroed report covers all of it:
    /// whether the key was pressed through the combo pages, the full keyboard or the
    /// direct-input capture, the keyboard state lives in one report, and clearing that is
    /// what tells the host nothing is down any more.
    private func _releaseHeldKeys() {
        sendKeyboard(.zero)
    }

    func updateBatteryLevel(_ level: UInt8) {
        let clamped = min(level, 100)
        batteryLevel = clamped
        let asHIDReport = Data([clamped])
        cachedReports[ReportID.battery.rawValue] = asHIDReport
        if let batteryLevelChar {
            _ = updateValue(asHIDReport, for: batteryLevelChar, reportID: ReportID.battery.rawValue)
        }
    }

    /// if host connects but never subscribes (stale GATT cache), cycle a temp service to fire Service Changed so it re-discovers
    func scheduleServiceChanged() {
        guard UserDefaults.standard.bool(forKey: AppSettings.useServiceChangedKey), !serviceChangedArmed else { return }
        serviceChangedArmed = true
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.serviceChangedGrace)
            self?._cycleServiceChangedIfUnsubscribed()
        }
    }

    private func _cycleServiceChangedIfUnsubscribed() {
        guard subscribedCentrals.isEmpty else { return }
        _cycleServiceChanged()
    }

    private func _cycleServiceChanged() {
        guard let pManager else { return }
        if let svc = serviceChangedObj {
            pManager.remove(svc)
            pManager.add(svc)
        } else {
            let svc = buildServiceChangedTrigger()
            serviceChangedObj = svc
            pManager.add(svc)
        }
        _trace("Service Changed cycled")
    }

    /// temp service used to perturb the GATT to trigger Service Changed
    private func buildServiceChangedTrigger() -> CBMutableService {
        let service = CBMutableService(type: CBUUID(nsuuid: UUID()), primary: true)
        service.characteristics = [
            CBMutableCharacteristic(
                type: CBUUID(nsuuid: UUID()),
                properties: [.read, .notifyEncryptionRequired],
                value: nil,
                permissions: .readEncryptionRequired
            )
        ]
        return service
    }

    private func installServices() {
        guard let pManager, !isHIDServiceAdded, batteryServiceObj == nil else { return }
        let battery = buildBatteryService()
        batteryServiceObj = battery
        pManager.add(battery)
    }

    private func buildDeviceInfoService() -> CBMutableService {
        let service = CBMutableService(type: HIDProfile.deviceInformationService, primary: true)
        service.characteristics = [
            CBMutableCharacteristic(
                type: HIDProfile.manufacturerName,
                properties: .read,
                value: HIDProfile.manufacturerNameValue,
                permissions: .readable
            ),
            CBMutableCharacteristic(
                type: HIDProfile.modelNumber,
                properties: .read,
                value: HIDProfile.modelNumberValue,
                permissions: .readable
            ),
            CBMutableCharacteristic(
                type: HIDProfile.pnpID,
                properties: .read,
                value: HIDProfile.pnpIDValue,
                permissions: .readable
            )
        ]
        return service
    }

    private func buildBatteryService() -> CBMutableService {
        let service = CBMutableService(type: HIDProfile.batteryService, primary: true)
        let level = CBMutableCharacteristic(
            type: HIDProfile.batteryLevel,
            properties: [.read, .notifyEncryptionRequired],
            value: nil,
            permissions: .readEncryptionRequired
        )
        // expose battery as HID Report ID 4 too
        let reportRef = CBMutableDescriptor(
            type: HIDProfile.reportReference,
            value: NSData(data: ReportID.battery.descriptor(.input))
        )
        level.descriptors = [reportRef]
        service.characteristics = [level]
        batteryLevelChar = level
        return service
    }

    private func buildHIDService(includingBattery battery: CBMutableService?) -> CBMutableService {
        let service = CBMutableService(type: HIDProfile.hidService, primary: true)
        if let battery { service.includedServices = [battery] }

        let controlPoint = CBMutableCharacteristic(
            type: HIDProfile.hidControlPoint,
            properties: .read,
            value: nil,
            permissions: .readEncryptionRequired
        )

        let protocolMode = CBMutableCharacteristic(
            type: HIDProfile.protocolMode,
            properties: [.read, .writeWithoutResponse],
            value: nil,
            permissions: [.readEncryptionRequired, .writeEncryptionRequired]
        )

        let hidInfo = CBMutableCharacteristic(
            type: HIDProfile.hidInformation,
            properties: .read,
            value: HIDProfile.hidInformationValue,
            permissions: .readEncryptionRequired
        )

        let bootMouseInput = CBMutableCharacteristic(
            type: HIDProfile.bootMouseInputReport,
            properties: [.read, .notifyEncryptionRequired],
            value: nil,
            permissions: [.readEncryptionRequired, .writeEncryptionRequired]
        )
        let bootKbdInput = CBMutableCharacteristic(
            type: HIDProfile.bootKeyboardInputReport,
            properties: [.read, .notifyEncryptionRequired],
            value: nil,
            permissions: [.readEncryptionRequired, .writeEncryptionRequired]
        )
        let bootKbdOutput = CBMutableCharacteristic(
            type: HIDProfile.bootKeyboardOutputReport,
            properties: [.read, .writeWithoutResponse, .write],
            value: nil,
            permissions: [.readEncryptionRequired, .writeEncryptionRequired]
        )

        // links the HID report map to battery level
        let reportMap = CBMutableCharacteristic(
            type: HIDProfile.reportMap,
            properties: .read,
            value: HIDProfile.reportMapData,
            permissions: .readEncryptionRequired
        )
        reportMap.descriptors = [
            CBMutableDescriptor(
                type: HIDProfile.externalReportReference,
                value: NSData(data: HIDProfile.externalReportReferenceValue)
            )
        ]

        // report characteristic order matters: keyboard first establishes keyboard primary identity
        let keyboardReportChar = makeReportChar(.keyboard, type: .input)
        let outputReportChar = CBMutableCharacteristic(
            type: HIDProfile.report,
            properties: [.read, .writeWithoutResponse, .write],
            value: nil,
            permissions: [.readEncryptionRequired, .writeEncryptionRequired]
        )
        outputReportChar.descriptors = [
            CBMutableDescriptor(
                type: HIDProfile.reportReference,
                value: NSData(data: ReportID.keyboardLEDs.descriptor(.output))
            )
        ]
        let mouseReportChar = makeReportChar(.mouse, type: .input)
        let systemReportChar = makeReportChar(.systemControl, type: .input)
        let consumerReportChar = makeReportChar(.consumerControl, type: .input)
        let digitizerReportChar = makeReportChar(.digitizer, type: .input)

        service.characteristics = [
            controlPoint,
            protocolMode,
            hidInfo,
            bootKbdInput,
            bootKbdOutput,
            bootMouseInput,
            reportMap,
            keyboardReportChar,
            outputReportChar,
            mouseReportChar,
            systemReportChar,
            consumerReportChar,
            digitizerReportChar
        ]

        bootMouseInputChar = bootMouseInput
        bootKeyboardInputChar = bootKbdInput
        bootKeyboardOutputChar = bootKbdOutput
        charsByReportID[ReportID.systemControl.rawValue] = systemReportChar
        charsByReportID[ReportID.consumerControl.rawValue] = consumerReportChar
        charsByReportID[ReportID.mouse.rawValue] = mouseReportChar
        charsByReportID[ReportID.keyboard.rawValue] = keyboardReportChar
        charsByReportID[ReportID.keyboardLEDs.rawValue] = outputReportChar
        charsByReportID[ReportID.digitizer.rawValue] = digitizerReportChar

        return service
    }

    private func makeReportChar(_ id: ReportID, type: ReportType) -> CBMutableCharacteristic {
        let char = CBMutableCharacteristic(
            type: HIDProfile.report,
            properties: [.read, .notifyEncryptionRequired],
            value: nil,
            permissions: .readEncryptionRequired
        )
        char.descriptors = [
            CBMutableDescriptor(type: HIDProfile.reportReference, value: NSData(data: id.descriptor(type)))
        ]
        return char
    }

    private func startAdvertisingNow() {
        guard let pManager, !isAdvertising else { return }
        pManager.startAdvertising([
            CBAdvertisementDataLocalNameKey: advertiseLocalName,
            // hidService must stay first if more than one service is being advertised
            CBAdvertisementDataServiceUUIDsKey: [HIDProfile.hidService]
        ])
    }

    private func broadcast(_ data: Data, reportID: ReportID) {
        cachedReports[reportID.rawValue] = data
        guard let char = charsByReportID[reportID.rawValue] else { return }
        _ = updateValue(data, for: char, reportID: reportID.rawValue)
    }

    @discardableResult
    private func updateValue(_ data: Data, for char: CBMutableCharacteristic, reportID: UInt8? = nil) -> Bool {
        guard let pManager else { return false }
        let recipients = activeRecipients()
        guard let target = activeCentral, !recipients.isEmpty else { return false }
        if !isReadyToSendNotification {
            park(data, for: char, reportID: reportID, target: target)
            return false
        }
        let accepted = pManager.updateValue(data, for: char, onSubscribedCentrals: recipients)
        if !accepted {
            // the queue is full: keep this report, replacing only an older one of its own kind
            isReadyToSendNotification = false
            park(data, for: char, reportID: reportID, target: target)
        }
        return accepted
    }

    /// Parks a report that could not be sent, keyed by report ID. Where the ID is unknown the
    /// characteristic stands in for it, so an unidentified report still cannot overwrite one
    /// from another characteristic.
    private func park(_ data: Data, for char: CBMutableCharacteristic, reportID id: UInt8?, target: UUID?) {
        pendingBroadcasts[id ?? reportID(forCharacteristic: char) ?? 0xF0] = (data, char, target)
    }

    /// Re-sends every parked report, oldest first. A report that fails again simply stays
    /// parked, and each ID is drained independently, so no report type can evict another.
    /// Only one host receives input, so a report parked by the host that lost control in
    /// the meantime is dropped rather than delivered to its replacement.
    private func drainPendingBroadcasts() {
        guard !pendingBroadcasts.isEmpty, let pManager else { return }
        for id in pendingBroadcasts.keys.sorted() {
            guard let entry = pendingBroadcasts[id] else { continue }
            // a report left over from a previous host is dropped: the host it was written
            // for no longer receives input. Congestion is left to report itself below, so
            // nothing is discarded while the active host is merely muted or away.
            guard entry.target == activeCentral else {
                pendingBroadcasts.removeValue(forKey: id)
                continue
            }
            let recipients = activeRecipients()
            guard !recipients.isEmpty else { return }
            if pManager.updateValue(entry.data, for: entry.char, onSubscribedCentrals: recipients) {
                pendingBroadcasts.removeValue(forKey: id)
            } else {
                // still congested: leave this one and everything after it parked
                isReadyToSendNotification = false
                return
            }
        }
    }

    private func _trace(_ message: @autoclosure () -> String) {
        guard UserDefaults.standard.bool(forKey: AppSettings.developerModeKey) else { return }
        let text = message()
        log.info("\(text, privacy: .public)")
    }

    private func _trackInteraction(from central: CBCentral) {
        centralObjects[central.identifier] = central
        guard !connectedCentrals.contains(central.identifier) else { return }
        connectedCentrals.insert(central.identifier)
        _trace("central tracked: \(central.identifier)")
    }

    /// Hosts that may receive input right now: the one active host, and only it.
    ///
    /// Every other subscriber stays linked at the Bluetooth level and receives nothing —
    /// a peripheral cannot drop one, so exclusivity here means exclusive *input*, not
    /// exclusive connection. Muting is a separate filter on top of that: it suppresses
    /// the active host's input without giving control to anyone else.
    private func activeRecipients() -> [CBCentral] {
        guard let activeCentral,
              subscribedCentrals[activeCentral] != nil,
              !inactiveCentrals.contains(activeCentral),
              !blockedCentrals.contains(activeCentral),
              let central = centralObjects[activeCentral]
        else { return [] }
        return [central]
    }

    private func reportID(forCharacteristic char: CBCharacteristic) -> UInt8? {
        for (id, c) in charsByReportID where c.uuid == char.uuid && c === char as AnyObject {
            return id
        }
        // fallback for restored characteristics
        if char.uuid == HIDProfile.report,
           let descriptor = (char as? CBMutableCharacteristic)?
           .descriptors?
           .first(where: { $0.uuid == HIDProfile.reportReference }),
           let value = descriptor.value as? Data,
           let id = value.first
        {
            return id
        }
        return nil
    }
}

extension HIDPeripheral: @preconcurrency CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        state = peripheral.state
        _trace("CB state -> \(peripheral.state.rawValue)")
        if peripheral.state == .poweredOn, isHIDServiceAllowed, !isHIDServiceAdded {
            installServices()
        }
        if peripheral.state != .poweredOn {
            isAdvertising = false
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error {
            log.error("didAddService(\(service.uuid)) error: \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
        }
        switch service.uuid {
        case HIDProfile.batteryService:
            let dis = buildDeviceInfoService()
            deviceInfoServiceObj = dis
            peripheral.add(dis)
        case HIDProfile.deviceInformationService:
            let hid = buildHIDService(includingBattery: batteryServiceObj)
            hidServiceObj = hid
            peripheral.add(hid)
        case HIDProfile.hidService:
            isHIDServiceAdded = true
            startAdvertisingNow()
        default:
            break
        }
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error {
            isAdvertising = false
            lastError = error.localizedDescription
            log.error("startAdvertising error: \(error.localizedDescription, privacy: .public)")
        } else {
            isAdvertising = true
            _trace("advertising as \(advertiseLocalName)")
        }
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didSubscribeTo characteristic: CBCharacteristic
    ) {
        _trackInteraction(from: central)
        subscribedCentrals[central.identifier, default: []].insert(characteristic.uuid)
        // subscribing is how a host reconnects, not a user action, so it carries no claim
        // to control: the first host claims an idle app, and after that only the user
        // switches. A host whose block survives the reconnect is not eligible at all.
        if activeCentral == nil, !blockedCentrals.contains(central.identifier) {
            activeCentral = central.identifier
            _trace("active host: \(central.identifier) (first claim)")
        }
        _trace("subscribe: \(central.identifier) -> \(characteristic.uuid)")
        // current state is brought up to date only for the host that receives input: on a
        // master report the characteristic header carries no central, so a replay would
        // otherwise be broadcast to the active host whichever host had subscribed
        guard activeCentral == central.identifier else { return }
        if let id = reportID(forCharacteristic: characteristic),
           let cached = cachedReports[id],
           let char = charsByReportID[id]
        {
            _ = updateValue(cached, for: char)
        } else if characteristic.uuid == HIDProfile.bootMouseInputReport, let bootMouseInputChar {
            _ = updateValue(MouseReport.zero.data, for: bootMouseInputChar)
        } else if characteristic.uuid == HIDProfile.bootKeyboardInputReport, let bootKeyboardInputChar {
            _ = updateValue(KeyboardReport.zero.data, for: bootKeyboardInputChar, reportID: ReportID.keyboard.rawValue)
        } else if characteristic.uuid == HIDProfile.batteryLevel, let batteryLevelChar {
            _ = updateValue(Data([batteryLevel]), for: batteryLevelChar, reportID: ReportID.battery.rawValue)
        }
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didUnsubscribeFrom characteristic: CBCharacteristic
    ) {
        _trace("unsubscribe: \(central.identifier) <- \(characteristic.uuid)")
        guard var chars = subscribedCentrals[central.identifier] else { return }
        chars.remove(characteristic.uuid)
        if chars.isEmpty {
            subscribedCentrals.removeValue(forKey: central.identifier)
            centralObjects.removeValue(forKey: central.identifier)
            inactiveCentrals.remove(central.identifier)
            connectedCentrals.remove(central.identifier)
            // a host that is gone cannot be the one receiving input, but one that was
            // removed keeps its block, so its reconnect still lands on a standby row
            if activeCentral == central.identifier {
                activeCentral = nil
            }
            serviceChangedArmed = false
        } else {
            subscribedCentrals[central.identifier] = chars
        }
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        isReadyToSendNotification = true
        drainPendingBroadcasts()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        _trace("read: \(request.central.identifier) -> \(request.characteristic.uuid)")
        _trackInteraction(from: request.central)
        scheduleServiceChanged()
        let value = readValue(forRequest: request)
        guard let value else {
            peripheral.respond(to: request, withResult: .invalidAttributeValueLength)
            return
        }
        guard request.offset <= value.count else {
            peripheral.respond(to: request, withResult: .invalidOffset)
            return
        }
        request.value = value.subdata(in: request.offset ..< value.count)
        peripheral.respond(to: request, withResult: .success)
    }

    private func readValue(forRequest request: CBATTRequest) -> Data? {
        switch request.characteristic.uuid {
        case HIDProfile.batteryLevel: return Data([batteryLevel])
        case HIDProfile.hidInformation: return HIDProfile.hidInformationValue
        case HIDProfile.reportMap: return HIDProfile.reportMapData
        case HIDProfile.protocolMode: return Data([0x01]) // report protocol
        case HIDProfile.manufacturerName: return HIDProfile.manufacturerNameValue
        case HIDProfile.modelNumber: return HIDProfile.modelNumberValue
        case HIDProfile.pnpID: return HIDProfile.pnpIDValue
        case HIDProfile.report:
            if let id = reportID(forCharacteristic: request.characteristic) {
                return cachedReports[id] ?? Data()
            }
            return Data()
        case HIDProfile.bootMouseInputReport: return cachedReports[ReportID.mouse.rawValue]
        case HIDProfile.bootKeyboardInputReport: return cachedReports[ReportID.keyboard.rawValue]
        default: return Data()
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            _trace("write: \(request.central.identifier) -> \(request.characteristic.uuid)")
            _trackInteraction(from: request.central)
            handleWriteRequest(request)
        }
        if let first = requests.first {
            peripheral.respond(to: first, withResult: .success)
        }
    }

    private func handleWriteRequest(_ request: CBATTRequest) {
        guard let value = request.value else { return }
        switch request.characteristic.uuid {
        case HIDProfile.bootKeyboardOutputReport:
            if let byte = value.first { keyboardLEDs = KeyboardLEDs(byte: byte) }
        case HIDProfile.report:
            if reportID(forCharacteristic: request.characteristic) == ReportID.keyboardLEDs.rawValue,
               let byte = value.first
            {
                keyboardLEDs = KeyboardLEDs(byte: byte)
            }
        case HIDProfile.protocolMode, HIDProfile.hidControlPoint:
            break
        default:
            break
        }
    }
}
