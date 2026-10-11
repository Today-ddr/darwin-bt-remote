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
    /// broadcasts skip inactive hosts; a muted host never receives input and can never hold
    /// control either, so that muting it cannot leave every report with nowhere to go
    @Published private(set) var inactiveCentrals: Set<UUID> = []
    @Published private(set) var connectedCentrals: Set<UUID> = []
    /// the one host that currently receives input. Control is sticky while its host is
    /// present: only the user switches it, and a host that reconnects can never take it from
    /// one that holds it. When the holder unsubscribes and leaves the list, control is handed
    /// to another host that is already subscribed instead of being left with nobody; see
    /// `handOverControl`.
    @Published private(set) var activeCentral: UUID?
    @Published private(set) var keyboardLEDs: KeyboardLEDs = []
    @Published private(set) var lastError: String?
    @Published private(set) var batteryLevel: UInt8 = 100

    private var centralObjects: [UUID: CBCentral] = [:]
    /// hosts the user removed from the list; they stay linked at the Bluetooth level
    /// but receive nothing until the user restores them. Persisted, because a removal is
    /// the user's own decision and has to outlive the launch that made it: an in-memory
    /// set would hand the host its input back the next time the app starts.
    private var blockedCentrals: Set<UUID> = Set(
        UserDefaults.standard.stringArray(forKey: AppSettings.blockedCentralsKey)?
            .compactMap(UUID.init(uuidString:)) ?? []
    )
    /// the order hosts subscribed in, so a handover can prefer the most recent one
    private var subscribeOrder: [UUID: UInt64] = [:]
    private var subscribeCounter: UInt64 = 0

    /// Whether anyone can receive input at all: the active host is still subscribed. Muting,
    /// removing or losing that host makes this false without clearing `activeCentral`, so the
    /// control state reads off one place instead of being re-derived from those sets, and
    /// input refused because this is false must not be parked as if it were merely waiting.
    var hasControl: Bool {
        activeCentral.map { subscribedCentrals[$0] != nil } ?? false
    }

    var advertiseLocalName: String = UserDefaults.standard.string(forKey: AppSettings.advertisedNameKey) ?? L10n.Bluetooth.advertisedName

    private let log = Logger(subsystem: "io.github.jqssun.btremote", category: "HIDPeripheral")
    /// The manager everything installed here hangs off. Releasing it — which the teardowns
    /// below do — is the only way to take the published services down and with them the links
    /// of the hosts that hold them; there is no way to disconnect a central directly.
    ///
    /// It is also the identity every delegate callback is checked against: a callback can
    /// outlive the manager that queued it, since CoreBluetooth offers neither an invalidate
    /// nor a cancel for `CBPeripheralManager`, so each callback drops one that is not the
    /// manager held right now. Without that check a late callback from a released manager
    /// would install services and advertise on the peripheral that replaced it, or let a
    /// subscriber of the old one claim control of the new one.
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
            _makeManager(showPowerAlert: true)
        } else if state == .poweredOn {
            if isHIDServiceAdded {
                startAdvertisingNow()
            } else {
                installServices()
            }
        }
    }

    /// Reads the radio's state without advertising.
    ///
    /// With advertising opt-in, nothing may be started at launch, but the Setup page still
    /// needs a truthful `state` before its button is ever tapped: it reads `.poweredOn` to
    /// decide between starting and complaining that Bluetooth is off, and a manager that
    /// does not exist yet reports `.unknown`, which that check would take for a dead radio.
    /// Bringing up the manager here only asks the system for the state — services are
    /// installed (and advertising begins) only through `start`.
    func observeState() {
        guard pManager == nil else { return }
        _makeManager(showPowerAlert: false)
    }

    /// Creates the manager both public ways in need, differing only in the power alert.
    private func _makeManager(showPowerAlert: Bool) {
        pManager = CBPeripheralManager(
            delegate: self,
            queue: nil,
            options: [CBPeripheralManagerOptionShowPowerAlertKey: showPowerAlert]
        )
    }

    /// Stop advertising; the way back in is `start`, which resumes from whatever point this
    /// left off. It is the user's own Stop Advertising — leaving the foreground goes through
    /// `suspend` instead, which ends the hosts' links as well. It deliberately keeps no
    /// opinion about why it was called: "we stopped it, bring it back" is the caller's own
    /// state — the scene phase is what knows it — and keeping that here would make a user's
    /// own stop indistinguishable from one that is meant to be undone. A host that is still
    /// subscribed keeps its link: this stops advertising, it does not end the connection.
    func stop() {
        isHIDServiceAllowed = false
        pManager?.stopAdvertising()
        isAdvertising = false
    }

    /// Suspend the peripheral: end advertising *and* the links hosts are holding, and leave
    /// a peripheral that `resume` rebuilds from nothing.
    ///
    /// `stop()` is not enough for this. It stops advertising, which only takes the app off
    /// the air for hosts that do not have it yet: a host that is already subscribed keeps
    /// its link, and a link that outlives the foreground keeps the radio busy — which is the
    /// wake-up this exists to end. CoreBluetooth gives a peripheral no way to disconnect a
    /// central, so the links come down with the manager that holds them, which is the
    /// teardown `_resetForRestart` has always performed; `_tearDownPeripheral` is that body,
    /// with what it takes down and what it deliberately leaves standing written out.
    ///
    /// It does not call that restart, because a suspend is not one: a restart is the power
    /// alert's "the radio was unusable, start over" and its caller starts again in the same
    /// breath, while a suspend is a stop with no promise of a return. The flag is where the
    /// difference shows: `isHIDServiceAllowed` goes false here, so a service cannot be
    /// installed into a peripheral that is meant to be down — a late callback from the
    /// manager being released, say. `start`/`resume` is what sets it true again.
    ///
    /// Nothing is surfaced by a suspend. Input stops because the app was taken away, not
    /// because it went nowhere, and the dropped-input notice goes with the teardown rather
    /// than sitting on screen through the suspension (see `_tearDownPeripheral`).
    func suspend() {
        _trace("suspend")
        isHIDServiceAllowed = false
        _tearDownPeripheral()
    }

    /// Bring back what `suspend` took down, and say again that the app wants to be found.
    ///
    /// The whole of a resume is `start()`: with the manager gone that builds one, and the
    /// install chain follows from the delegate callbacks — services, then advertising —
    /// exactly as it does at launch. So this is an intent and nothing else: advertising is
    /// not claimed here, `isAdvertising` is neither set nor cleared by it, and a resume that
    /// has returned has not necessarily advertised yet.
    ///
    /// Whether a resume is wanted at all is the caller's own question, and `BTRemoteApp`
    /// answers it with the bit it keeps for that: only what this app suspended is resumed,
    /// so a Stop Advertising the user tapped stays stopped and a launch resumes nothing.
    func resume() {
        _trace("resume")
        start()
    }

    func promptPowerAlert() {
        guard state != .poweredOn else { return }
        _resetForRestart()
        start()
    }

    /// The power alert's way of starting over: the radio reported something other than
    /// `.poweredOn`, so nothing installed on the old manager is trusted and the whole
    /// peripheral — services and links with it — is taken apart before `start` builds it
    /// again. That is the same teardown a suspend performs, minus the one thing that makes a
    /// suspend a stop: `isHIDServiceAllowed` is left exactly as it was, because this path
    /// starts again immediately.
    private func _resetForRestart() {
        _tearDownPeripheral()
    }

    /// Takes the peripheral apart: releases the manager — which is what removes the
    /// published services and drops every host's link, the only way to drop one — and then
    /// clears the objects and bookkeeping that were built around it, so a later `start`
    /// rebuilds from nothing. It is the body `_resetForRestart` has always had, shared with
    /// `suspend` so the two cannot drift apart: both need the chain gone, and neither may
    /// keep anything that names the old manager's services, characteristics or subscribers.
    ///
    /// What it deliberately leaves standing is part of its contract, because both callers
    /// depend on it:
    ///
    /// - `blockedCentrals` — the hosts the user removed. That set is the user's own decision
    ///   and is persisted for exactly that reason, so it outlives any link; clearing it here
    ///   would resurrect a host the user removed, which is the bug the persistent list was
    ///   written to fix. A restart already kept it and a suspend must too.
    /// - `state` — the last state the radio reported. There is a manager again as soon as
    ///   `start` runs (which is what `resume` is for), and until its first callback lands,
    ///   this is what the Setup page's Start Advertising button reads to choose between
    ///   starting and complaining about the radio: a teardown that reset it to `.unknown`
    ///   would send that tap down the power-alert branch for a radio that is on.
    ///   `observeState` exists for the same reason at launch.
    /// - the state that belongs to the device rather than to a link: `advertiseLocalName`,
    ///   `batteryLevel`, `keyboardLEDs` and the cached reports.
    ///
    /// `isHIDServiceAllowed` is not touched here either: the two callers mean different
    /// things by it, and each sets it the way its own semantics require.
    private func _tearDownPeripheral() {
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
        // link state, all of it: the subscribers, the live `CBCentral` objects and the
        // connected set were the old manager's knowledge and do not survive releasing it
        subscribedCentrals.removeAll()
        // a mute is a filter on a link rather than a decision about the host — it already
        // goes when the host unsubscribes (`didUnsubscribeFrom`) — so it goes with the link
        // here too. Only the block list outlives a link (see the note above).
        inactiveCentrals.removeAll()
        connectedCentrals.removeAll()
        centralObjects.removeAll()
        // control starts clean. No host is connected after a teardown, so the first host to
        // subscribe claims the idle peripheral the same way it does on a cold start —
        // `didSubscribeTo` claims only when nothing holds control, so there is nobody for a
        // reconnect to steal it from. Leaving the old host active would point control at a
        // host that is gone, and a resume would then read as input being routed while
        // nothing is subscribed.
        activeCentral = nil
        subscribeOrder.removeAll()
        subscribeCounter = 0
        // the notice says reports are being dropped. A teardown ends every link on purpose,
        // so leaving it up would describe a deliberate act, and nothing would retract it
        // while no host is subscribed: `_clearDroppedInputNoticeIfHeld` needs a report to
        // reach a host, which cannot happen until one subscribes again.
        if lastError == Self.droppedInputNotice {
            lastError = nil
        }
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

    /// Mute or unmute a host. Muting is a filter on top of control, never a way to hand it
    /// over: a muted host holds nothing and the host that holds control keeps it, so the two
    /// filters never contradict each other (both are what the row's state is read from, see
    /// `DeviceEntry`). Unmuting the host that holds control lets it receive again, so a report
    /// parked while it was muted — a key-up, typically — is retried here rather than left
    /// waiting for some later ping to flush it.
    func toggleActive(_ uuid: UUID) {
        if inactiveCentrals.contains(uuid) {
            inactiveCentrals.remove(uuid)
        } else {
            inactiveCentrals.insert(uuid)
        }
        _trace("mute \(uuid): \(inactiveCentrals.contains(uuid))")
        _reportDroppedInputIfNone()
        _drainIfUnblocked()
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
        // the host would be left holding whatever was down when control was taken away.
        // Control is then left on nobody rather than handed to another subscriber: a removal
        // must not silently reroute input, so it stays dead until the user restores the row
        // or a host subscribes again. The notice in `_reportDroppedInputIfNone` is what keeps
        // that from being invisible.
        let wasActive = activeCentral == uuid
        if wasActive {
            _releaseHeldKeys()
            activeCentral = nil
        }
        blockedCentrals.insert(uuid)
        _saveBlockedCentrals()
        inactiveCentrals.remove(uuid)
        objectWillChange.send()
    }

    func isBlocked(_ uuid: UUID) -> Bool {
        blockedCentrals.contains(uuid)
    }

    /// Undo `removeCentral`, the way back for a host that is still subscribed. A host that
    /// is gone is eligible to claim control when it next subscribes, provided nothing holds
    /// it by then (see the claim in `didSubscribeTo`).
    ///
    /// Unblocking does not hand control back: the host that held it before the removal was
    /// cleared, so the retry below only picks up input parked while this host was blocked —
    /// it never takes control from a host that holds it. Restoring a muted host stays muted.
    func restoreCentral(_ uuid: UUID) {
        blockedCentrals.remove(uuid)
        _saveBlockedCentrals()
        objectWillChange.send()
        _reportDroppedInputIfNone()
        _drainIfUnblocked()
    }

    /// Writes the whole set on every change, the way `DeviceNameStore` writes its map: one
    /// key holds one list, so there is no per-host bookkeeping to keep in step with the set
    /// itself. UUID strings are stored because a `Set<UUID>` is not a plist type.
    private func _saveBlockedCentrals() {
        UserDefaults.standard.set(
            blockedCentrals.map(\.uuidString).sorted(),
            forKey: AppSettings.blockedCentralsKey
        )
    }

    /// Make a subscribed, unblocked and unmuted host the one that receives input, replacing
    /// whatever held control — no reconnecting needed, the hosts stay linked throughout.
    ///
    /// Muting is a separate filter and the two states are meant to be read together: a muted
    /// host's row stays on Standby because it cannot receive input, and making it active
    /// anyway would leave every report with nowhere to go — no recipient, so nothing is
    /// parked and nothing is sent — while the row showed it as In Use. Refusing here keeps
    /// what is displayed and what is routed the same thing.
    ///
    /// Keys that are still down are released before the input is rerouted, so the host
    /// losing control is not left with a latched key.
    func makeActive(_ uuid: UUID) {
        guard subscribedCentrals[uuid] != nil,
              !blockedCentrals.contains(uuid),
              !inactiveCentrals.contains(uuid),
              activeCentral != uuid
        else { return }
        // the host losing control is told that nothing is held any more, and the new one
        // starts from the same quiet baseline rather than whatever it last knew
        _releaseHeldKeys()
        activeCentral = uuid
        _releaseHeldKeys()
        _trace("active host: \(uuid)")
        // the previous host's parked reports go, and this host's own backlog — a key-up
        // parked while it was muted, for one — is retried now that it can receive again
        _dropParkedBroadcastsFromPreviousHost()
        _drainIfUnblocked()
    }

    /// Releases everything a host could be holding. One zeroed report covers all of it:
    /// whether the key was pressed through the combo pages, the full keyboard or the
    /// direct-input capture, the keyboard state lives in one report, and clearing that is
    /// what tells the host nothing is down any more.
    private func _releaseHeldKeys() {
        sendKeyboard(.zero)
    }

    /// Gives control to a subscribed, unblocked and unmuted host after the one that held it
    /// was lost. The most recently subscribed one wins: a reconnect is automatic, so the
    /// host that came back last is the one the user most likely just sat down at.
    ///
    /// This cannot reopen the silent steal the sticky `activeCentral` was built to stop. It
    /// is only ever called when that variable is nil, i.e. when the host that held control
    /// stopped being subscribed, and it never runs from a fresh subscribe that arrives while
    /// another host holds control: `didSubscribeTo` claims control only when `hasControl`
    /// says nobody holds it, which a handover has just made true only for a host that is
    /// already subscribed. A host that subscribes to a peripheral that is not idle stays on
    /// Standby, and the only other way in remains the user's own switch, `makeActive`.
    ///
    /// Promotion is not a second claim from a muted or removed host: both are filtered out
    /// here exactly as they are in `activeRecipients`.
    private func handOverControl() {
        // only ever called on a loss of control, but the condition is restated rather than
        // assumed: promoting from anywhere else is the silent steal this feature forbids, so
        // the one thing that decides is whether control is free right now
        guard hasControl == false else { return }
        let next = subscribedCentrals.keys
            .filter { uuid in
                !blockedCentrals.contains(uuid) && !inactiveCentrals.contains(uuid)
            }
            .max { subscribeOrder[$0] ?? 0 < subscribeOrder[$1] ?? 0 }
        guard let next else { return }
        activeCentral = next
        _trace("active host: \(next) (handover)")
        // the report of the host that just lost control goes with it, and the new one is
        // told nothing is held. `didSubscribeTo` is left to replay its cached state where
        // that applies, so a host is not brought up to date twice over a subscribe.
        _dropParkedBroadcastsFromPreviousHost()
        _releaseHeldKeys()
        _drainIfUnblocked()
    }

    /// Whether there is anything parked to retry. Kept as its own step because the two things
    /// that can unblock a drain do not both promise that: `handOverControl` runs on every
    /// subscribe, almost all of which happen while one host holds control and nothing is
    /// parked at all.
    private var hasParkedBroadcasts: Bool {
        !pendingBroadcasts.isEmpty
    }

    /// Retries a parked report as soon as whatever refused it is gone: a mute that has been
    /// lifted, a host restored, control moved to a host that can receive. Where input was
    /// refused there is nothing parked to lose, so this only runs when something is actually
    /// waiting, which is what keeps it from spinning: no timer, no repeat, one drain attempt
    /// per change of state, and the attempt itself is the same one congestion already uses.
    /// A send that is refused again because the queue is full re-parks the report and defers
    /// to `peripheralManagerIsReady`, exactly as before.
    private func _drainIfUnblocked() {
        guard hasParkedBroadcasts, hasControl else { return }
        isReadyToSendNotification = true
        drainPendingBroadcasts()
    }

    /// Whether input is going nowhere: nobody holds control, or the host that does cannot
    /// receive it — muted, blocked, or no longer linked to us at the Bluetooth level. This is
    /// exactly the condition that makes an input drop silent, and the one the notice speaks
    /// for. `hasControl` is not the same thing: a muted or unlinked host still reads as
    /// holding control while every report is dropped.
    private var isDroppingInput: Bool {
        activeRecipients().isEmpty
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
        guard let target = activeCentral, !recipients.isEmpty else {
            _reportDroppedInputIfNone()
            return false
        }
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
    /// from another characteristic. The target is the host the report was written for, which
    /// is whoever was receiving input when it was parked: input that had no host to go to was
    /// dropped where it was written, not parked, so a parked report is never re-routed to a
    /// host that turns up later (see `updateValue` and `_reportDroppedInputIfNone`).
    private func park(_ data: Data, for char: CBMutableCharacteristic, reportID id: UInt8?, target: UUID?) {
        pendingBroadcasts[id ?? reportID(forCharacteristic: char) ?? 0xF0] = (data, char, target)
    }

    /// Re-sends every parked report, oldest first. A report that fails again simply stays
    /// parked, and each ID is drained independently, so no report type can evict another.
    /// Only one host receives input, so a report parked by the host that lost control in
    /// the meantime is dropped rather than delivered to its replacement.
    ///
    /// Congestion is what this drain remains for: a report that is refused again here leaves
    /// the flag false, so `peripheralManagerIsReady` is what brings the next attempt. Being
    /// called again sooner than that is fine — a mute that has been lifted is one of the
    /// things that brings it, so a key-up that was parked before the mute is not stranded
    /// until a new report happens to be written (see `_drainIfUnblocked`).
    private func drainPendingBroadcasts() {
        guard hasParkedBroadcasts, let pManager else { return }
        for id in pendingBroadcasts.keys.sorted() {
            guard let entry = pendingBroadcasts[id] else { continue }
            // a report left over from a previous host is dropped: the host it was written
            // for no longer receives input. Congestion is left to report itself below, so
            // nothing is discarded while the active host is merely muted or away.
            guard entry.target == activeCentral else {
                pendingBroadcasts.removeValue(forKey: id)
                continue
            }
            // no recipient is why it was parked, not something to spin on: leave it parked
            // and let the change that makes a recipient available retry it
            let recipients = activeRecipients()
            guard !recipients.isEmpty else { return }
            guard pManager.updateValue(entry.data, for: entry.char, onSubscribedCentrals: recipients) else {
                // the queue is full: the flag goes false so the next attempt comes from
                // `peripheralManagerIsReady`, as it always has, and this entry and the rest
                // stay parked behind it
                isReadyToSendNotification = false
                _clearDroppedInputNoticeIfHeld()
                return
            }
            pendingBroadcasts.removeValue(forKey: id)
            _clearDroppedInputNoticeIfHeld()
        }
    }

    /// Input that reached no host at all: nothing was parked, so it is gone and the run of
    /// silent drops ends here.
    ///
    /// `lastError` is the one channel `HIDPeripheral` has for saying something is wrong, and
    /// the section it feeds is shown while input is being dropped, so the notice goes there.
    /// A silent dead input was the whole problem: the host keeps the key it last saw, the
    /// performer taps to a screen that answers nothing, and no state anywhere said why. This
    /// names the state only; it deliberately carries no instruction, so it stays meaningful
    /// when nobody can be given control to fix it and it needed no new string.
    /// The notice itself, in the app's own words for a host that is not receiving input. It
    /// is also its identity: it is retracted by comparing the slot to this, so no second
    /// piece of state has to be kept in step with what is displayed, and it is read once
    /// rather than per dropped report, which can be every mouse move.
    private static let droppedInputNotice = String(localized: "device.inactive")

    private func _reportDroppedInputIfNone() {
        guard isDroppingInput, isHIDServiceAdded, lastError != Self.droppedInputNotice else { return }
        lastError = Self.droppedInputNotice
        _trace("no active host: input dropped")
    }

    /// Retracts the notice above the moment a report reaches a host, and only that notice: an
    /// error from somewhere else in the engine keeps its slot, and of two identical strings
    /// sitting there it is this one that is cleared.
    private func _clearDroppedInputNoticeIfHeld() {
        guard isDroppingInput == false, lastError == Self.droppedInputNotice else { return }
        lastError = nil
    }

    /// Retracts a report that was parked for the host that just lost control, the way a
    /// switch discards it during a drain: the next host should not receive input the old one
    /// was meant to get. It is what draining used to do when a switch moved the target, and
    /// the switch and the handover would otherwise have to wait for a drain of their own.
    private func _dropParkedBroadcastsFromPreviousHost() {
        for (id, entry) in pendingBroadcasts where entry.target != nil && entry.target != activeCentral {
            pendingBroadcasts.removeValue(forKey: id)
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
        guard peripheral === pManager else { return }
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
        // this is the callback a teardown can arrive in the middle of. Dropping it does not
        // strand the install chain: what it leaves behind was cleared with the manager, and
        // the `start` after the teardown lays it again from the first service.
        guard peripheral === pManager else { return }
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
        guard peripheral === pManager else { return }
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
        // a host working the old manager, mid-teardown: nothing it does may claim control or
        // be replayed a report, so it is dropped rather than booked against the new manager
        guard peripheral === pManager else { return }
        _trackInteraction(from: central)
        subscribeCounter += 1
        subscribeOrder[central.identifier] = subscribeCounter
        subscribedCentrals[central.identifier, default: []].insert(characteristic.uuid)
        // subscribing is how a host reconnects, not a user action, so it carries no claim
        // to control: the first host claims an idle app, and after that only the user
        // switches. Nothing holds control while input is going nowhere, so a host that
        // arrives after a removal claims it back the same way. Muting is the other end of
        // the same rule the rest of the engine keeps — a muted host holds nothing, even
        // when it is the only one there. A silent steal is what this claim must never
        // become: it fires only when no host at all is active, never over one that is.
        if !hasControl, !blockedCentrals.contains(central.identifier), !inactiveCentrals.contains(central.identifier) {
            activeCentral = central.identifier
            _trace("active host: \(central.identifier) (first claim)")
        }
        _trace("subscribe: \(central.identifier) -> \(characteristic.uuid)")
        // input refused while nobody could hold it is retried once someone does, so a
        // report that was cut off by a removal reaches the host that takes over
        _drainIfUnblocked()
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
        guard peripheral === pManager else { return }
        _trace("unsubscribe: \(central.identifier) <- \(characteristic.uuid)")
        guard var chars = subscribedCentrals[central.identifier] else { return }
        chars.remove(characteristic.uuid)
        if chars.isEmpty {
            subscribedCentrals.removeValue(forKey: central.identifier)
            centralObjects.removeValue(forKey: central.identifier)
            inactiveCentrals.remove(central.identifier)
            connectedCentrals.remove(central.identifier)
            subscribeOrder.removeValue(forKey: central.identifier)
            serviceChangedArmed = false
            // a host that is gone cannot be the one receiving input. Control has to go
            // somewhere: leaving it on nobody stops every later report with no error and no
            // recovery, because the hosts still connected never subscribe again and so never
            // claim. A muted host is released from the set here rather than left to filter
            // the handover out, so the host that leaves takes only its own state with it.
            if activeCentral == central.identifier {
                activeCentral = nil
                handOverControl()
            }
        } else {
            subscribedCentrals[central.identifier] = chars
        }
        // covers the one case a handover cannot: the host that left was the last one, so
        // input now has nowhere to go and says so instead of stopping silently. When control
        // found a home above, this finds a host receiving input and does nothing.
        _reportDroppedInputIfNone()
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        guard peripheral === pManager else { return }
        isReadyToSendNotification = true
        drainPendingBroadcasts()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        guard peripheral === pManager else { return }
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
        guard peripheral === pManager else { return }
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
