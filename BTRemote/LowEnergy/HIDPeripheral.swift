import Combine
import CoreBluetooth
import os
import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

/// Identity of one parked report.
///
/// A report ID alone is not an identity: the main keyboard report and the boot keyboard
/// report both carry `ReportID.keyboard`, and they live in different characteristics with
/// independent send queues. Keying on the ID alone let a boot key-up overwrite the parked
/// main key-up (or the other way round), so one of the two hosts never saw its release.
/// The characteristic's object identity is what actually separates the two destinations;
/// the report ID is kept so diagnostics can name the kind of report.
///
/// The target is part of the identity as well. A switch of control sends the old host a
/// release and then the new host one on the same characteristic and report ID; without the
/// target the two zero reports shared one slot, so the old host's release was overwritten
/// by the new host's and then filtered out as belonging to neither — the old host kept the
/// key down. With the target in the key each host owns its own slot and both can wait for
/// their queue at the same time.
struct HIDPendingBroadcastKey: Hashable {
    let reportID: UInt8
    let characteristic: ObjectIdentifier
    let target: UUID
}

/// HID-over-GATT peripheral engine
@MainActor
final class HIDPeripheral: NSObject, ObservableObject {
    @Published private(set) var state: CBManagerState = .unknown
    @Published private(set) var isAdvertising = false
    @Published private(set) var isHIDServiceAdded = false
    /// central identifier: the actual characteristic instances it is currently subscribed to.
    ///
    /// Object identity, not `CBUUID`: every HID report characteristic shares UUID 0x2A4D,
    /// so a set of UUIDs cannot tell the keyboard report from the mouse report, and
    /// notifying one would have been indistinguishable from notifying the other.
    @Published private(set) var subscribedCentrals: [UUID: Set<ObjectIdentifier>] = [:]
    /// broadcasts skip inactive hosts; a muted host never receives input and can never hold
    /// control either, so that muting it cannot leave every report with nowhere to go
    @Published private(set) var inactiveCentrals: Set<UUID> = []
    @Published private(set) var connectedCentrals: Set<UUID> = []
    /// the host that last held control. It is sticky while that host can actually receive:
    /// only the user switches it, and a host that reconnects cannot take it from one that
    /// holds it. While the named host is muted or removed `hasControl` is false, so a new
    /// eligible subscriber claims it in `didSubscribeTo`; when the holder unsubscribes and
    /// leaves the list, `handOverControl` gives it to another subscribed host instead of
    /// leaving it with nobody.
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

    /// Whether anyone can receive input at all: the active host is still subscribed, is
    /// not muted and is not removed. Muting, removing or losing that host makes this false
    /// without clearing `activeCentral`, so the control state reads off one place instead
    /// of being re-derived from those sets. A muted or removed host therefore cannot keep
    /// control away from a host that arrives later: `didSubscribeTo` claims when this is
    /// false.
    var hasControl: Bool {
        !activeRecipients().isEmpty
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
    /// Whether services may exist at all. It is the "expose" half of the power state and
    /// survives `stop()`: stopping advertising must not take down services a host is still
    /// using, and the install chain that was already running must be allowed to finish.
    private var isHIDServiceAllowed = false
    /// Whether the user wants to be discoverable. `stop()` clears only this; a late
    /// `didAdd`/`didStartAdvertising` callback must not advertise after it has gone false.
    private var isAdvertisingRequested = false
    /// A start request that has been handed to CoreBluetooth but whose callback has not
    /// arrived yet. Without it a second `startAdvertisingNow` — the state callback and the
    /// install chain can both reach it — would ask the manager to start twice; the duplicate
    /// request either fails or makes the two callbacks race over `isAdvertising`.
    private var isAdvertisingPending = false
    private var isReadyToSendNotification = true
    /// The two intents as they were when `suspend` took the peripheral apart, so `resume`
    /// restores exactly what was running rather than the maximum.
    private var wasServiceAllowedBeforeSuspend = false
    private var wasAdvertisingRequestedBeforeSuspend = false
    /// Protocol Mode characteristic value: 0x01 report protocol, 0x00 boot protocol.
    /// HOGP lets a host switch it, so the read has to answer with what was written.
    private var currentProtocolMode: UInt8 = 0x01
    /// The last advertising error put into `lastError`, so a later success clears that
    /// message without touching an unrelated error.
    private var lastAdvertisingError: String?

    private var charsByReportID: [UInt8: CBMutableCharacteristic] = [:]
    private var bootMouseInputChar: CBMutableCharacteristic?
    private var bootKeyboardInputChar: CBMutableCharacteristic?
    private var batteryLevelChar: CBMutableCharacteristic?
    private var serviceChangedObj: CBMutableService?
    private var serviceChangedArmed = false
    private static let serviceChangedGrace: UInt64 = 2_000_000_000

    /// last-sent payloads for reads and new subscriptions
    private var cachedReports: [UInt8: Data] = HIDPeripheral.zeroInputReports

    private static var zeroInputReports: [UInt8: Data] {
        [
            ReportID.mouse.rawValue: MouseReport.zero.data,
            ReportID.keyboard.rawValue: KeyboardReport.zero.data
        ]
    }

    /// Key used when a battery notification has to be parked. Battery is a standard GATT
    /// characteristic rather than a HID report, so it has no `ReportID`; this byte only keeps
    /// its parked entry distinct from the reports that do.
    private static let batteryNotificationID: UInt8 = 0x04

    /// One parked payload per (report ID, characteristic instance, target host). A single
    /// slot per ID let any later report evict a parked one, and keying by ID alone still
    /// made the main and boot keyboard reports overwrite each other — a key-up waiting on
    /// the send queue could be silently replaced and never reach the host, which then
    /// repeated the key forever because it still believed the key was held.
    ///
    /// Each entry also remembers the host it was addressed to. Only one host receives input
    /// at a time, so anything still queued at a switch belongs to the host that just lost
    /// control; ordinary input is dropped rather than replayed on the new host. A release is
    /// the exception: it is the report that clears what that old host may still be holding,
    /// so it stays addressable while the old host is subscribed (see
    /// `_dropParkedBroadcastsFromPreviousHost` and `drainPendingBroadcasts`).
    private struct PendingBroadcast {
        let data: Data
        let char: CBMutableCharacteristic
        let target: UUID
        /// Whether this is a zero report written to release held input. Releases are
        /// routed differently from input: they may reach a host that no longer holds
        /// control, and a mute or removal must not stop them from clearing a stuck key.
        let isRelease: Bool
        let sequence: UInt64
    }

    private var pendingBroadcasts: [HIDPendingBroadcastKey: PendingBroadcast] = [:]
    /// Monotonic across the life of the peripheral; the drain uses it to preserve the order
    /// in which reports were written, independent of dictionary iteration order.
    private var parkSequence: UInt64 = 0

    func start() {
        // Both intents are explicit: services may be exposed, and the user asked to be
        // discoverable. The install chain is asynchronous, so neither is inferred from a
        // callback that may not have run yet.
        isHIDServiceAllowed = true
        isAdvertisingRequested = true
        if pManager == nil {
            _makeManager(showPowerAlert: true)
            return
        }
        guard state == .poweredOn else { return }
        if isHIDServiceAdded {
            startAdvertisingNow()
        } else {
            installServices()
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

    /// Stop advertising, and only that.
    ///
    /// Services stay installed and a host that is still subscribed keeps its link: this is
    /// the user's own Stop Advertising and it means "do not let new hosts find me", not
    /// "throw out the host I am using". The separate `isAdvertisingRequested` flag is what
    /// a late install callback consults, so tapping Stop while the services are still being
    /// added cannot be undone by `didAdd` arriving afterwards. Leaving the foreground goes
    /// through `suspend` instead, which ends the links as well.
    func stop() {
        isAdvertisingRequested = false
        pManager?.stopAdvertising()
        isAdvertising = false
        // a start still in flight is no longer wanted; its callback is ignored because the
        // request is false, and the flag is cleared here so a later Start is not refused by
        // a pending bit that will never be retired by the ignored callback
        isAdvertisingPending = false
    }

    /// Whether the peripheral is on the air in any sense: advertising, holding services a
    /// host could be or already is connected to, or in the middle of bringing either up.
    ///
    /// This is the test for "is there something to take down", and `isAdvertising` alone is
    /// not it. `stop()` stops advertising but leaves the services and the links alone, so
    /// after the user taps Stop Advertising the app is still reachable by a subscribed host
    /// while `isAdvertising == false`; suspending on that flag would skip the teardown and
    /// leave the link — and the radio — alive through the whole time in the background.
    ///
    /// `isHIDServiceAllowed` and `isAdvertisingRequested` cover the install window: between
    /// `start()` and the services being installed there is no advertising and no service
    /// yet, but the app is on its way up, and a background landing in that window still has
    /// to take it down again.
    var isOnTheAir: Bool {
        isHIDServiceAllowed || isAdvertisingRequested || isAdvertising || isHIDServiceAdded
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
    /// Both intents are remembered before they are cleared, and both are cleared here: a
    /// service must not be installed into a peripheral that is meant to be down, and a late
    /// advertising callback must not put it back on the air. `resume` restores the two
    /// independently, so a suspension that found only a live link does not switch
    /// advertising on for a user who had tapped Stop.
    ///
    /// Nothing is surfaced by a suspend. Input stops because the app was taken away, not
    /// because it went nowhere, and the dropped-input notice goes with the teardown rather
    /// than sitting on screen through the suspension (see `_tearDownPeripheral`).
    func suspend() {
        _trace("suspend")
        wasServiceAllowedBeforeSuspend = isHIDServiceAllowed
        wasAdvertisingRequestedBeforeSuspend = isAdvertisingRequested
        isHIDServiceAllowed = false
        isAdvertisingRequested = false
        _tearDownPeripheral()
    }

    /// Bring back what `suspend` took down.
    ///
    /// The two remembered intents are restored independently. Services are rebuilt whenever
    /// they were allowed before the suspension, even if advertising was already off — that
    /// is the C2 this fixes: `start()` used to be the only path that rebuilt anything, and a
    /// suspension that interrupted only a live link came back through `observeState`, which
    /// installs nothing, so the services never returned. Advertising is requested again only
    /// when it was requested before; otherwise the rebuilt peripheral stays off the air.
    ///
    /// Whether a resume is wanted at all is the caller's own question, and `BTRemoteApp`
    /// answers it with the bit it keeps for that: only what this app suspended is resumed,
    /// so a Stop Advertising the user tapped stays stopped and a launch resumes nothing.
    ///
    /// A new manager installs through its delegate callbacks, so this returns before the
    /// services exist; it is an intent, not a completed install.
    func resume() {
        _trace("resume")
        let serviceAllowed = wasServiceAllowedBeforeSuspend
        let advertisingRequested = wasAdvertisingRequestedBeforeSuspend
        wasServiceAllowedBeforeSuspend = false
        wasAdvertisingRequestedBeforeSuspend = false
        isHIDServiceAllowed = serviceAllowed
        isAdvertisingRequested = advertisingRequested
        guard serviceAllowed else {
            observeState()
            return
        }
        if pManager == nil {
            // the install chain follows `peripheralManagerDidUpdateState` on the new manager
            _makeManager(showPowerAlert: false)
            return
        }
        guard state == .poweredOn else { return }
        if isHIDServiceAdded {
            if advertisingRequested {
                startAdvertisingNow()
            }
        } else {
            installServices()
        }
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
    /// The intent flags are not touched here: the two callers mean different things by them
    /// (`suspend` clears both before calling, `_resetForRestart` leaves them for `start`).
    ///
    /// What survives is deliberately only what belongs to the device rather than to a link:
    /// `blockedCentrals`, `state`, `advertiseLocalName` and `batteryLevel`. Input reports are
    /// reset to zero by `_clearLinkState`, so a host that subscribes after a rebuild can
    /// never be replayed the previous link's held key.
    private func _tearDownPeripheral() {
        pManager?.stopAdvertising()
        pManager = nil
        isAdvertising = false
        _clearLinkState()
    }

    /// Drops everything that names the current manager's services, characteristics, links
    /// and input state. Used both when the manager is released and when the radio reports a
    /// state other than `.poweredOn`; in the latter case the manager itself stays so it can
    /// report the radio coming back.
    ///
    /// The input report cache is reset to zero — a release baseline — rather than kept, so
    /// a new subscription after a power cycle or a resume cannot be handed the key that was
    /// held when the old link died. Battery is not input: `batteryLevel` belongs to the
    /// device and is kept.
    private func _clearLinkState() {
        isHIDServiceAdded = false
        // the manager the request belonged to is gone (or the radio went away), so that
        // callback either never comes or is dropped by the identity check above
        isAdvertisingPending = false
        isReadyToSendNotification = true
        pendingBroadcasts.removeAll()
        batteryServiceObj = nil
        serviceChangedObj = nil
        serviceChangedArmed = false
        batteryLevelChar = nil
        bootMouseInputChar = nil
        bootKeyboardInputChar = nil
        charsByReportID.removeAll()
        // link state, all of it: the subscribers, the live `CBCentral` objects and the
        // connected set were the old manager's knowledge and do not survive it
        subscribedCentrals.removeAll()
        // a mute is a filter on a link rather than a decision about the host — it already
        // goes when the host unsubscribes (`didUnsubscribeFrom`) — so it goes with the link
        // here too. Only the block list outlives a link.
        inactiveCentrals.removeAll()
        connectedCentrals.removeAll()
        centralObjects.removeAll()
        // control starts clean: the first host to subscribe claims the idle peripheral the
        // same way it does on a cold start. Leaving the old host active would point control
        // at a host that is gone.
        activeCentral = nil
        subscribeOrder.removeAll()
        subscribeCounter = 0
        keyboardLEDs = []
        currentProtocolMode = 0x01
        // input goes back to the release baseline; battery belongs to the device and is
        // read from `batteryLevel`, not from this cache
        cachedReports = Self.zeroInputReports
        // the notice says reports are being dropped. A teardown ends every link on purpose,
        // so leaving it up would describe a deliberate act, and nothing would retract it
        // while no host is subscribed: `_clearDroppedInputNoticeIfHeld` needs a report to
        // reach a host, which cannot happen until one subscribes again.
        if lastError == Self.droppedInputNotice {
            lastError = nil
        }
    }

    func sendMouse(_ report: MouseReport) {
        _sendMouse(report, isRelease: false)
    }

    func sendKeyboard(_ report: KeyboardReport) {
        _sendKeyboard(report, isRelease: false)
    }

    /// The one place a mouse report is written, with whether it is a release travelling
    /// alongside it. The public entry points above always send input; `_releaseHeldInput`
    /// is the only caller that marks a report as a release.
    ///
    /// The Boot Mouse Input characteristic is written only for the host that actually
    /// subscribes to it. Boot hosts read that characteristic instead of the main mouse
    /// report, and it has a 3-byte layout without the wheel, so the main 4-byte report is
    /// never copied there.
    private func _sendMouse(_ report: MouseReport, isRelease: Bool) {
        broadcast(report.data, reportID: .mouse, isRelease: isRelease)
        guard let bootChar = bootMouseInputChar else { return }
        _ = updateValue(
            report.bootData,
            for: bootChar,
            reportID: ReportID.mouse.rawValue,
            isRelease: isRelease
        )
    }

    /// The same split for the keyboard: the main report and the boot report carry the same
    /// release flag, so both protocol variants can clear a key that is still down.
    private func _sendKeyboard(_ report: KeyboardReport, isRelease: Bool) {
        broadcast(report.data, reportID: .keyboard, isRelease: isRelease)
        // Boot-protocol hosts read this characteristic instead. `updateValue` only writes it
        // to a host that actually subscribed to this instance; a host in report protocol
        // never subscribes here, so it receives nothing and no report is parked for it.
        guard let bootChar = bootKeyboardInputChar else { return }
        _ = updateValue(
            report.data,
            for: bootChar,
            reportID: ReportID.keyboard.rawValue,
            isRelease: isRelease
        )
    }

    /// Mute or unmute a host. Muting is a filter on top of control, never a way to hand it
    /// over: a muted host holds nothing and the host that holds control keeps it, so the two
    /// filters never contradict each other (both are what the row's state is read from, see
    /// `DeviceEntry`). Unmuting the host that holds control lets it receive again, so a
    /// release that congestion parked while it was muted is retried here rather than left
    /// waiting for some later ping to flush it.
    func toggleActive(_ uuid: UUID) {
        if inactiveCentrals.contains(uuid) {
            inactiveCentrals.remove(uuid)
        } else {
            inactiveCentrals.insert(uuid)
        }
        _trace("mute \(uuid): \(inactiveCentrals.contains(uuid))")
        _reportDroppedInputIfNone()
        // unmuting the active host makes it a recipient again; a notice raised by the mute
        // has to come down even when nothing was parked to retry
        _clearDroppedInputNoticeIfHeld()
        _drainIfUnblocked()
    }

    /// Stop sending input to a host until the user restores it.
    ///
    /// CoreBluetooth exposes no way for a peripheral to drop a single central —
    /// `CBPeripheralManager` has no counterpart to `cancelPeripheralConnection`,
    /// and removing the service does not notify the peer (it only makes this side
    /// lose track of its subscribers). So the link itself survives and the host stays
    /// in the connected list, marked as removed. There it receives no new input until the
    /// user restores it: the block outlives unsubscribes and reconnects, so a host
    /// that comes back on its own does not get a second chance at the input. A release
    /// already parked for it may still be written, because clearing held state is not input
    /// (see `drainPendingBroadcasts`).
    func removeCentral(_ uuid: UUID) {
        // Release before the host is cut off. This runs even when the host is muted: the
        // release is the last chance to clear what it may still be holding, and the block is
        // applied below. Control is then left on nobody rather than handed to another
        // subscriber: a removal must not silently reroute input, so it stays dead until the
        // user restores the row or a host subscribes again. The notice in
        // `_reportDroppedInputIfNone` is what keeps that from being invisible.
        let wasActive = activeCentral == uuid
        if wasActive {
            _releaseHeldInput()
        }
        if wasActive {
            activeCentral = nil
        }
        blockedCentrals.insert(uuid)
        _saveBlockedCentrals()
        inactiveCentrals.remove(uuid)
        if wasActive {
            _dropParkedBroadcastsFromPreviousHost()
            // a release parked for the host that was just removed is still deliverable:
            // the link is alive and the report only clears state. Control being nil is not
            // a reason to leave it waiting for a queue callback that may never come.
            _drainIfUnblocked()
        }
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

    /// Clears the user state this engine owns outside `UserDefaults`, for the Settings
    /// "reset everything" path: the removal list is kept in memory as well as on disk, and
    /// the advertised name is cached in a stored property, so deleting the defaults domain
    /// alone would leave both alive until the next launch.
    ///
    /// If advertising was requested, stop/start is what makes the restored name visible: the
    /// advertisement payload is a snapshot taken when advertising starts, and there is no
    /// way to update it in place. The test is the request rather than `isAdvertising` because
    /// the start may still be in flight: a callback that lands after the reset must advertise
    /// the restored name, not the old one.
    func resetUserState() {
        blockedCentrals.removeAll()
        _saveBlockedCentrals()
        advertiseLocalName = L10n.Bluetooth.advertisedName
        lastError = nil
        // the cached message is also the identity used to clear a stale error on success;
        // leaving it set would make a later success keep pointing at the reset-away failure
        lastAdvertisingError = nil
        if isAdvertisingRequested {
            stop()
            start()
        }
        objectWillChange.send()
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
    /// Every input the old host could be holding is released before the reroute, and the new
    /// host starts from a full zero baseline — keyboard and mouse, not just the keys of the
    /// last report.
    func makeActive(_ uuid: UUID) {
        guard holdsInputSubscription(uuid),
              !blockedCentrals.contains(uuid),
              !inactiveCentrals.contains(uuid),
              activeCentral != uuid
        else { return }
        // The host losing control is told that nothing is held any more, even if it is muted:
        // a release is not input, and a key that was down before the mute would otherwise
        // stay down on that host. The release still only reaches a host that is linked and
        // subscribed (see `updateValue`).
        _releaseHeldInput()
        activeCentral = uuid
        _releaseHeldInput()
        _trace("active host: \(uuid)")
        // the previous host's parked reports go, and this host's own backlog — a key-up
        // parked while it was muted, for one — is retried now that it can receive again
        _dropParkedBroadcastsFromPreviousHost()
        _drainIfUnblocked()
    }

    /// Releases every kind of input a host could be holding: keyboard keys and modifiers, and
    /// mouse buttons (with any unfinished motion). One zeroed report per characteristic is
    /// what tells the host nothing is down any more; a report type nobody is subscribed to
    /// quietly does nothing.
    ///
    /// Everything written here is marked as a release. That is what lets it survive a switch
    /// of control: the previous host's release is still delivered after the new host has
    /// taken over, even though ordinary input for the old host is dropped.
    private func _releaseHeldInput() {
        _sendKeyboard(.zero, isRelease: true)
        _sendMouse(.zero, isRelease: true)
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
                holdsInputSubscription(uuid)
                    && !blockedCentrals.contains(uuid)
                    && !inactiveCentrals.contains(uuid)
            }
            .max { subscribeOrder[$0] ?? 0 < subscribeOrder[$1] ?? 0 }
        guard let next else { return }
        activeCentral = next
        _trace("active host: \(next) (handover)")
        // the report of the host that just lost control goes with it, and the new one is
        // given a complete zero baseline — keyboard and mouse — so it cannot inherit a held
        // state from the host that left. `didSubscribeTo` is left to replay its cached state
        // where that applies, so a host is not brought up to date twice over a subscribe.
        _dropParkedBroadcastsFromPreviousHost()
        _releaseHeldInput()
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
    ///
    /// `hasControl` is not a precondition here: a parked release still has a destination
    /// when no host holds control — that is exactly the `removeCentral` case — and the drain
    /// applies the control gate to ordinary input alone.
    private func _drainIfUnblocked() {
        guard hasParkedBroadcasts else { return }
        isReadyToSendNotification = true
        drainPendingBroadcasts()
    }

    /// Whether input is going nowhere: nobody holds control, or the host that does cannot
    /// receive it — muted, blocked, or no longer linked to us at the Bluetooth level. This
    /// is exactly the condition that makes an input drop silent, and the one the notice
    /// speaks for. A report type the active host happens not to subscribe to is *not* this
    /// condition: it is not an error to be subscribed to the keyboard but not the mouse.
    private var isDroppingInput: Bool {
        activeRecipients().isEmpty
    }

    /// Reads the device's own battery and publishes it as the HID battery level.
    ///
    /// Monitoring has to be enabled before `UIDevice.batteryLevel` reports anything other
    /// than -1. A negative value means the level is not known yet, and leaves the published
    /// level at whatever it was rather than inventing 0%. This is a UIKit-only, foreground
    /// read: no background task or new entitlement is involved.
    func refreshBatteryLevel() {
        #if canImport(UIKit)
            UIDevice.current.isBatteryMonitoringEnabled = true
            let level = UIDevice.current.batteryLevel
            guard level >= 0 else { return }
            updateBatteryLevel(UInt8((level * 100).rounded()))
        #endif
    }

    func updateBatteryLevel(_ level: UInt8) {
        batteryLevel = min(level, 100)
        // Battery is device state, not input: it goes to every host that actually subscribed
        // to the battery characteristic, even if none of them holds input control. No
        // subscriber is a normal state here and must never raise the dropped-input notice.
        guard let batteryLevelChar, let pManager else { return }
        let report = Data([batteryLevel])
        let recipients = subscribedCentrals.compactMap { uuid, chars -> CBCentral? in
            guard chars.contains(ObjectIdentifier(batteryLevelChar)),
                  !blockedCentrals.contains(uuid)
            else { return nil }
            return centralObjects[uuid]
        }
        guard !recipients.isEmpty else { return }
        _ = pManager.updateValue(report, for: batteryLevelChar, onSubscribedCentrals: recipients)
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
        // one attempt per arming: a host that read and left without ever subscribing would
        // otherwise leave the flag set for the rest of the session, and the next host could
        // never trigger the cycle at all. The grace above is what stops it from repeating
        // faster than a host can discover.
        serviceChangedArmed = false
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
        guard isHIDServiceAllowed, let pManager, !isHIDServiceAdded, batteryServiceObj == nil else { return }
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
        // The battery is a plain Battery Service (0x180F / 0x2A19). It is not a HID report,
        // so it carries no Report Reference descriptor pointing into the report map.
        service.characteristics = [level]
        batteryLevelChar = level
        return service
    }

    private func buildHIDService(includingBattery battery: CBMutableService?) -> CBMutableService {
        let service = CBMutableService(type: HIDProfile.hidService, primary: true)
        if let battery {
            service.includedServices = [battery]
        }

        // HOGP: the control point is written (suspend / exit suspend), not read. It carries
        // no value this peripheral acts on, but declaring it writable is what lets a host
        // send the command and get a response instead of leaving the ATT write unanswered.
        let controlPoint = CBMutableCharacteristic(
            type: HIDProfile.hidControlPoint,
            properties: [.writeWithoutResponse],
            value: nil,
            permissions: .writeEncryptionRequired
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

        let reportMap = CBMutableCharacteristic(
            type: HIDProfile.reportMap,
            properties: .read,
            value: HIDProfile.reportMapData,
            permissions: .readEncryptionRequired
        )

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
            mouseReportChar
        ]

        bootMouseInputChar = bootMouseInput
        bootKeyboardInputChar = bootKbdInput
        charsByReportID[ReportID.mouse.rawValue] = mouseReportChar
        charsByReportID[ReportID.keyboard.rawValue] = keyboardReportChar
        charsByReportID[ReportID.keyboardLEDs.rawValue] = outputReportChar

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
        // the request, not the callback, is the authority: a Stop tapped while the install
        // chain was still running clears it, and a late `didAdd` must not put the radio back
        // on the air behind the user's back. `isAdvertisingPending` is the same idea for a
        // request that is already in flight: the powered-on callback and the end of the
        // install chain can both arrive and must not start advertising twice.
        guard isAdvertisingRequested,
              let pManager,
              isHIDServiceAdded,
              state == .poweredOn,
              !isAdvertising,
              !isAdvertisingPending
        else { return }
        isAdvertisingPending = true
        pManager.startAdvertising([
            CBAdvertisementDataLocalNameKey: advertiseLocalName,
            // hidService must stay first if more than one service is being advertised
            CBAdvertisementDataServiceUUIDsKey: [HIDProfile.hidService]
        ])
    }

    private func broadcast(_ data: Data, reportID: ReportID, isRelease: Bool) {
        cachedReports[reportID.rawValue] = data
        guard let char = charsByReportID[reportID.rawValue] else { return }
        _ = updateValue(data, for: char, reportID: reportID.rawValue, isRelease: isRelease)
    }

    /// Sends one report on one characteristic.
    ///
    /// `reportsDrop` separates "input reached nobody" from "this characteristic has no
    /// subscriber". Only the first is the dropped-input state; battery, for example, may
    /// legitimately have no subscriber and must not make the Setup page claim input is
    /// being dropped. The recipients are the active host filtered by whether *this*
    /// characteristic instance is in its subscription set — every report characteristic
    /// shares UUID 0x2A4D, so a UUID check cannot make that distinction.
    ///
    /// `isRelease` marks the zero report `_releaseHeldInput` writes. It is carried into the
    /// parked entry so a release survives a switch of control and is routed by its own
    /// target rather than by whoever is active when the queue recovers. On the send path it
    /// also bypasses the mute/block filter: the host is cleared as long as it is still
    /// subscribed, so a host that was muted while holding a key cannot keep it down.
    @discardableResult
    private func updateValue(
        _ data: Data,
        for char: CBMutableCharacteristic,
        reportID: UInt8,
        reportsDrop: Bool = true,
        isRelease: Bool = false
    ) -> Bool {
        guard let pManager else { return false }
        guard let target = activeCentral else {
            if reportsDrop {
                _reportDroppedInputIfNone()
            }
            return false
        }
        let recipients: [CBCentral]
        if isRelease {
            // A release is allowed to reach the host it is clearing even when that host is
            // muted or removed: the report only says "nothing is held", and leaving a key
            // down is worse than a zero the filter did not ask for. The link is still the
            // gate — no live central object or no subscription means nowhere to write.
            guard subscribedCentrals[target]?.contains(ObjectIdentifier(char)) == true,
                  let central = centralObjects[target]
            else { return false }
            recipients = [central]
        } else {
            guard hasControl else {
                if reportsDrop {
                    _reportDroppedInputIfNone()
                }
                return false
            }
            recipients = activeRecipients(for: char)
            guard !recipients.isEmpty else {
                // the host holds control but is not subscribed to this characteristic: there
                // is nowhere for this report to go, and that is not the dropped-input state
                return false
            }
        }
        if !isReadyToSendNotification {
            park(data, for: char, reportID: reportID, target: target, isRelease: isRelease)
            return false
        }
        let accepted = pManager.updateValue(data, for: char, onSubscribedCentrals: recipients)
        if accepted {
            // a report just reached a host, so the "nothing is receiving this" notice no longer
            // describes anything. This is the ordinary path and it has to retract the notice
            // itself: clearing it only in `drainPendingBroadcasts` left it stranded, because a
            // teardown empties the parked queue, so after a suspend/resume the drain returns
            // early and the notice had no way back off the screen.
            _clearDroppedInputNoticeIfHeld()
        } else {
            // the queue is full: keep this report, replacing only an older one of its own
            // (report ID, characteristic, target) triple
            isReadyToSendNotification = false
            park(data, for: char, reportID: reportID, target: target, isRelease: isRelease)
        }
        return accepted
    }

    /// Parks a report that could not be sent, keyed by the characteristic instance, the
    /// report ID and the target host. Two characteristics that share UUID 0x2A4D — the main
    /// and boot keyboard reports, for instance — therefore own independent slots and can
    /// never overwrite each other's key-up. The target in the key is what lets the old host's
    /// release and the new host's release coexist during a switch: both are zero reports on
    /// the same characteristic, and only the host they are addressed to tells them apart.
    ///
    /// A parked report is never re-routed to a host that turns up later: input that had no
    /// host to go to was dropped where it was written, not parked (see `updateValue` and
    /// `_reportDroppedInputIfNone`).
    private func park(
        _ data: Data,
        for char: CBMutableCharacteristic,
        reportID: UInt8,
        target: UUID,
        isRelease: Bool
    ) {
        parkSequence += 1
        let key = HIDPendingBroadcastKey(
            reportID: reportID,
            characteristic: ObjectIdentifier(char),
            target: target
        )
        pendingBroadcasts[key] = PendingBroadcast(
            data: data,
            char: char,
            target: target,
            isRelease: isRelease,
            sequence: parkSequence
        )
    }

    /// Re-sends every parked report, oldest first. A report that fails again simply stays
    /// parked, and each (report ID, characteristic, target) triple is drained independently,
    /// so no report type, characteristic or host can evict another.
    ///
    /// Congestion is what this drain remains for: a report that is refused again here leaves
    /// the flag false, so `peripheralManagerIsReady` is what brings the next attempt. Being
    /// called again sooner than that is fine — a mute that has been lifted is one of the
    /// things that brings it, so a key-up that was parked before the mute is not stranded
    /// until a new report happens to be written (see `_drainIfUnblocked`).
    ///
    /// Ordinary input goes only to the active host. A release goes to the host named by its
    /// own entry, which may have lost control since it was parked; it is allowed to reach a
    /// host that is now muted or removed, because the zero report only clears state and a
    /// host left believing a key is down is the worse outcome. What still drops a release is
    /// the link itself: no live central object or no subscription to that characteristic
    /// means there is nowhere to write it.
    private func drainPendingBroadcasts() {
        guard hasParkedBroadcasts, let pManager else { return }
        let ordered = pendingBroadcasts
            .map { ($0.key, $0.value) }
            .sorted { $0.1.sequence < $1.1.sequence }
        for (key, entry) in ordered {
            // the snapshot can name an entry that has since been replaced or removed
            guard pendingBroadcasts[key] != nil else { continue }
            let recipients: [CBCentral]
            if entry.isRelease {
                guard let central = centralObjects[entry.target],
                      subscribedCentrals[entry.target]?.contains(key.characteristic) == true
                else {
                    pendingBroadcasts.removeValue(forKey: key)
                    continue
                }
                recipients = [central]
            } else {
                // a report left over from a previous host is dropped: the host it was written
                // for no longer receives input
                guard entry.target == activeCentral else {
                    pendingBroadcasts.removeValue(forKey: key)
                    continue
                }
                // no recipient is why it was parked, not something to spin on: leave it parked
                // and let the change that makes a recipient available retry it. This gate is
                // for ordinary input only — returning here for a release would leave the old
                // host's key-up stranded once `removeCentral` has cleared `activeCentral`.
                guard hasControl else { continue }
                let active = activeRecipients(for: entry.char)
                guard !active.isEmpty else {
                    // the active host no longer subscribes to this characteristic, so this
                    // entry can never reach it; drop it instead of keeping it forever
                    pendingBroadcasts.removeValue(forKey: key)
                    continue
                }
                recipients = active
            }
            guard pManager.updateValue(entry.data, for: entry.char, onSubscribedCentrals: recipients) else {
                // the queue is full: the flag goes false so the next attempt comes from
                // `peripheralManagerIsReady`, as it always has, and this entry and the rest
                // stay parked behind it
                isReadyToSendNotification = false
                _clearDroppedInputNoticeIfHeld()
                return
            }
            pendingBroadcasts.removeValue(forKey: key)
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

    /// Retracts reports parked for the host that just lost control. Ordinary input is
    /// discarded: the next host should not receive what the old one was meant to get. A
    /// release is different — it is the zero report that clears what the old host may still
    /// be holding, so it stays parked while that host is linked and subscribed to the
    /// characteristic it was written for. Muting or removing the host does not filter it
    /// out: the user's input filters decide who receives new input, not whether an already
    /// held key may be cleared. The key snapshot is taken first because removing from a
    /// dictionary while iterating it is not supported.
    private func _dropParkedBroadcastsFromPreviousHost() {
        for key in Array(pendingBroadcasts.keys) {
            guard let entry = pendingBroadcasts[key] else { continue }
            if entry.target == activeCentral {
                continue
            }
            if entry.isRelease,
               centralObjects[entry.target] != nil,
               subscribedCentrals[entry.target]?.contains(key.characteristic) == true
            {
                continue
            }
            pendingBroadcasts.removeValue(forKey: key)
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
    /// the active host's input without giving control to anyone else, and because this
    /// returns empty for a muted host, `hasControl` is false while it is muted.
    private func activeRecipients() -> [CBCentral] {
        guard let activeCentral,
              holdsInputSubscription(activeCentral),
              !inactiveCentrals.contains(activeCentral),
              !blockedCentrals.contains(activeCentral),
              let central = centralObjects[activeCentral]
        else { return [] }
        return [central]
    }

    /// Whether this host subscribes to at least one characteristic that carries input. Only
    /// the main keyboard/mouse reports and their boot counterparts count: a host that only
    /// subscribed to battery level (or to the output report) cannot receive input, so it
    /// must not hold control away from a host that can.
    private func holdsInputSubscription(_ uuid: UUID) -> Bool {
        guard let subscriptions = subscribedCentrals[uuid] else { return false }
        if let bootKeyboardInputChar, subscriptions.contains(ObjectIdentifier(bootKeyboardInputChar)) {
            return true
        }
        if let bootMouseInputChar, subscriptions.contains(ObjectIdentifier(bootMouseInputChar)) {
            return true
        }
        if let keyboard = charsByReportID[ReportID.keyboard.rawValue],
           subscriptions.contains(ObjectIdentifier(keyboard))
        {
            return true
        }
        if let mouse = charsByReportID[ReportID.mouse.rawValue],
           subscriptions.contains(ObjectIdentifier(mouse))
        {
            return true
        }
        return false
    }

    /// The same recipient, restricted to hosts that are actually subscribed to this
    /// characteristic instance. `CBUUID` cannot be the test: all HID report
    /// characteristics share 0x2A4D, so only object identity distinguishes the keyboard
    /// report from the mouse report, or the main report from the boot report.
    private func activeRecipients(for char: CBMutableCharacteristic) -> [CBCentral] {
        guard let activeCentral,
              subscribedCentrals[activeCentral]?.contains(ObjectIdentifier(char)) == true,
              !inactiveCentrals.contains(activeCentral),
              !blockedCentrals.contains(activeCentral),
              let central = centralObjects[activeCentral]
        else { return [] }
        return [central]
    }

    /// Abandons a partially installed service chain after CoreBluetooth rejected a service.
    ///
    /// `CBPeripheralManager` keeps the services that were already added, so a failure in the
    /// middle of the chain would leave the peripheral half-installed — a battery service
    /// without the HID service, or a HID service without its report map — and nothing would
    /// ever finish the install. Removing every service and clearing the objects that named
    /// them returns the engine to the state before `installServices`; the next user Start
    /// runs the chain again from the first service.
    ///
    /// No retry is started here. A rejection that does not go away would turn an automatic
    /// retry into a loop, so the failure is surfaced through `lastError` and the install stays
    /// down until the user asks again (or a radio event leads back through `installServices`).
    private func _abandonFailedInstall(_ error: Error) {
        pManager?.stopAdvertising()
        pManager?.removeAllServices()
        isAdvertising = false
        isAdvertisingPending = false
        isHIDServiceAdded = false
        batteryServiceObj = nil
        serviceChangedObj = nil
        serviceChangedArmed = false
        batteryLevelChar = nil
        bootMouseInputChar = nil
        bootKeyboardInputChar = nil
        charsByReportID.removeAll()
        lastError = error.localizedDescription
    }

    /// The report ID of a characteristic we installed. Identity only: a peripheral manager
    /// has no restore identifier, so there is no such thing as a restored characteristic
    /// here, and a UUID lookup would confuse the report characteristics that share 0x2A4D.
    private func reportID(forCharacteristic char: CBCharacteristic) -> UInt8? {
        charsByReportID.first { $0.value === char as AnyObject }?.key
    }
}

extension HIDPeripheral: @preconcurrency CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        guard peripheral === pManager else { return }
        state = peripheral.state
        _trace("CB state -> \(peripheral.state.rawValue)")
        guard peripheral.state == .poweredOn else {
            // The radio went away: every service, subscription, link and input state that
            // named the old session is gone with it. The manager itself stays so it can
            // report the radio coming back, and the two intents stay so the rebuild knows
            // whether to expose services and whether to advertise once they are up.
            isAdvertising = false
            _clearLinkState()
            return
        }
        // The radio is back: restart whatever the two intents say should exist. The service
        // side is closed here rather than left for the next `start` — a manager that already
        // holds its services only has to advertise, and one that does not has to install
        // them, including after an install failure cleared a half-built chain.
        if isHIDServiceAllowed {
            if isHIDServiceAdded {
                startAdvertisingNow()
            } else {
                installServices()
            }
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        // this is the callback a teardown can arrive in the middle of. Dropping it does not
        // strand the install chain: what it leaves behind was cleared with the manager, and
        // the `start` after the teardown lays it again from the first service.
        guard peripheral === pManager else { return }
        if let error {
            // A failure must not fall through to the switch below: the service was not added,
            // so treating it as a completed step would mark a HID service that does not exist
            // as added and try to advertise it. The whole partial chain goes instead.
            log.error("didAddService(\(service.uuid)) error: \(error.localizedDescription, privacy: .public)")
            switch service.uuid {
            case HIDProfile.batteryService, HIDProfile.deviceInformationService, HIDProfile.hidService:
                _abandonFailedInstall(error)
            default:
                // The service-changed trigger is added outside the install chain, after a
                // host has already read something. A failure there must not take down a HID
                // service that is working and linked: surface it and forget the trigger so a
                // later arming can try again.
                lastError = error.localizedDescription
                serviceChangedObj = nil
            }
            return
        }
        switch service.uuid {
        case HIDProfile.batteryService:
            peripheral.add(buildDeviceInfoService())
        case HIDProfile.deviceInformationService:
            let hid = buildHIDService(includingBattery: batteryServiceObj)
            peripheral.add(hid)
        case HIDProfile.hidService:
            isHIDServiceAdded = true
            // the chain is complete, so an add error left by an earlier failed install is
            // stale: Setup must not keep showing it now that the services are back up
            lastError = nil
            // `startAdvertisingNow` checks the intent, so a Stop during the install chain
            // is not undone by this late callback
            startAdvertisingNow()
        default:
            break
        }
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        guard peripheral === pManager else { return }
        // the request this callback answers is finished either way; keeping the flag set
        // would make every later start look like a duplicate and never advertise again
        isAdvertisingPending = false
        // the user may have tapped Stop while the request was in flight; the callback must
        // not switch advertising back on behind their back
        guard isAdvertisingRequested else {
            if isAdvertising {
                peripheral.stopAdvertising()
            }
            isAdvertising = false
            return
        }
        if let error {
            isAdvertising = false
            let message = error.localizedDescription
            lastAdvertisingError = message
            lastError = message
            log.error("startAdvertising error: \(message, privacy: .public)")
        } else {
            isAdvertising = true
            // a stale advertising error would otherwise sit on the Setup page forever
            if let lastAdvertisingError, lastError == lastAdvertisingError {
                lastError = nil
            }
            lastAdvertisingError = nil
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
        // the characteristic instance, not its UUID: every report characteristic shares
        // 0x2A4D, so a UUID set could not tell the keyboard report from the mouse report
        subscribedCentrals[central.identifier, default: []].insert(ObjectIdentifier(characteristic))
        // subscribing is how a host reconnects, not a user action, so it carries no claim
        // to control: the first host claims an idle app, and after that only the user
        // switches. `hasControl` is false while the active host is muted or removed, so a
        // new host that is neither can take over instead of being locked out by a host that
        // cannot receive anything. A silent steal is what this claim must never become: it
        // fires only when no host can receive, never over one that can.
        if !hasControl,
           holdsInputSubscription(central.identifier),
           !blockedCentrals.contains(central.identifier),
           !inactiveCentrals.contains(central.identifier)
        {
            activeCentral = central.identifier
            _trace("active host: \(central.identifier) (first claim)")
            // a new host must not inherit anything the previous link held, and whatever was
            // parked for that link is not this host's to receive
            _dropParkedBroadcastsFromPreviousHost()
            _releaseHeldInput()
        }
        _trace("subscribe: \(central.identifier) -> \(characteristic.uuid)")
        // input refused while nobody could hold it is retried once someone does, so a
        // report that was cut off by a removal reaches the host that takes over
        _drainIfUnblocked()
        // current state is brought up to date only for the host that receives input, and on
        // the very characteristic it subscribed to: a master report characteristic carries
        // no central identity, so replaying through `charsByReportID` would send on a
        // different instance that this host may never have subscribed to
        guard activeCentral == central.identifier,
              let char = characteristic as? CBMutableCharacteristic
        else { return }
        if let id = reportID(forCharacteristic: char), let cached = cachedReports[id] {
            _ = updateValue(cached, for: char, reportID: id, reportsDrop: false)
        } else if characteristic.uuid == HIDProfile.bootMouseInputReport {
            // boot protocol: 3 bytes with no wheel; the main 4-byte report must not be
            // replayed onto this characteristic
            _ = updateValue(MouseReport.zero.bootData, for: char, reportID: ReportID.mouse.rawValue, reportsDrop: false)
        } else if characteristic.uuid == HIDProfile.bootKeyboardInputReport {
            _ = updateValue(KeyboardReport.zero.data, for: char, reportID: ReportID.keyboard.rawValue, reportsDrop: false)
        } else if characteristic.uuid == HIDProfile.batteryLevel {
            _ = updateValue(
                Data([batteryLevel]),
                for: char,
                reportID: Self.batteryNotificationID,
                reportsDrop: false
            )
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
        chars.remove(ObjectIdentifier(characteristic))
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
            // the host is still linked, but if the characteristic it just dropped was its
            // last one carrying input, it can no longer hold control; hand it to a host
            // that still can rather than leaving every report addressed to this one
            if activeCentral == central.identifier, !holdsInputSubscription(central.identifier) {
                activeCentral = nil
                _dropParkedBroadcastsFromPreviousHost()
                handOverControl()
            }
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
        guard request.offset <= value.count else {
            peripheral.respond(to: request, withResult: .invalidOffset)
            return
        }
        request.value = value.subdata(in: request.offset ..< value.count)
        peripheral.respond(to: request, withResult: .success)
    }

    private func readValue(forRequest request: CBATTRequest) -> Data {
        switch request.characteristic.uuid {
        case HIDProfile.batteryLevel: return Data([batteryLevel])
        case HIDProfile.hidInformation: return HIDProfile.hidInformationValue
        case HIDProfile.reportMap: return HIDProfile.reportMapData
        case HIDProfile.protocolMode: return Data([currentProtocolMode])
        case HIDProfile.manufacturerName: return HIDProfile.manufacturerNameValue
        case HIDProfile.modelNumber: return HIDProfile.modelNumberValue
        case HIDProfile.pnpID: return HIDProfile.pnpIDValue
        case HIDProfile.report:
            if let id = reportID(forCharacteristic: request.characteristic) {
                return cachedReports[id] ?? Data()
            }
            return Data()
        case HIDProfile.bootMouseInputReport:
            // a read of an input characteristic answers with the idle baseline, not the
            // main mouse report: boot layout is 3 bytes and has no wheel byte
            return MouseReport.zero.bootData
        case HIDProfile.bootKeyboardInputReport: return cachedReports[ReportID.keyboard.rawValue] ?? Data()
        default: return Data()
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        guard peripheral === pManager else { return }
        // Every request in the batch needs its own response. Responding only to the first
        // leaves the others waiting on an ATT transaction that will never complete, and the
        // host then stalls its next write — the keyboard LED output, for one.
        for request in requests {
            _trace("write: \(request.central.identifier) -> \(request.characteristic.uuid)")
            _trackInteraction(from: request.central)
            let result = handleWriteRequest(request)
            peripheral.respond(to: request, withResult: result)
        }
    }

    /// Applies one write and returns the ATT result for it.
    private func handleWriteRequest(_ request: CBATTRequest) -> CBATTError.Code {
        guard let value = request.value else { return .invalidAttributeValueLength }
        switch request.characteristic.uuid {
        case HIDProfile.bootKeyboardOutputReport:
            if let byte = value.first {
                keyboardLEDs = KeyboardLEDs(byte: byte)
            }
        case HIDProfile.report:
            if reportID(forCharacteristic: request.characteristic) == ReportID.keyboardLEDs.rawValue,
               let byte = value.first
            {
                keyboardLEDs = KeyboardLEDs(byte: byte)
            }
        case HIDProfile.protocolMode:
            // 0x00 boot protocol, 0x01 report protocol; remember it so a read answers with
            // the mode the host selected instead of a hard-coded value
            if let mode = value.first {
                currentProtocolMode = mode
            }
        case HIDProfile.hidControlPoint:
            // suspend / exit suspend: no local behavior to apply, but the write is accepted
            break
        default:
            break
        }
        return .success
    }
}
