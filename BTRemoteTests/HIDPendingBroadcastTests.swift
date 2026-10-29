@testable import BTRemote
import XCTest

/// The parked-report key has to distinguish three things that can otherwise collide: two
/// characteristics that carry the same report ID (the main and boot keyboard report are
/// both Report ID 2 on UUID 0x2A4D), and two hosts that receive the same zero report during
/// a switch of control. Keying by ID alone let one overwrite the other's key-up; keying
/// without the target let the new host's release evict the old host's. These use plain
/// objects for identity — the key is `ObjectIdentifier`-based, so CoreBluetooth is not
/// needed to prove the property.
final class HIDPendingBroadcastTests: XCTestCase {
    func testTheSameReportIDOnDifferentCharacteristicsIsADifferentKey() {
        let mainKeyboardReport = NSObject()
        let bootKeyboardReport = NSObject()
        let host = UUID()

        let main = HIDPendingBroadcastKey(
            reportID: ReportID.keyboard.rawValue,
            characteristic: ObjectIdentifier(mainKeyboardReport),
            target: host
        )
        let boot = HIDPendingBroadcastKey(
            reportID: ReportID.keyboard.rawValue,
            characteristic: ObjectIdentifier(bootKeyboardReport),
            target: host
        )

        XCTAssertNotEqual(main, boot)
        XCTAssertEqual(Set([main, boot]).count, 2)
    }

    func testDifferentReportIDsOnOneCharacteristicAreDifferentKeys() {
        let characteristic = NSObject()
        let host = UUID()

        let keyboard = HIDPendingBroadcastKey(
            reportID: ReportID.keyboard.rawValue,
            characteristic: ObjectIdentifier(characteristic),
            target: host
        )
        let mouse = HIDPendingBroadcastKey(
            reportID: ReportID.mouse.rawValue,
            characteristic: ObjectIdentifier(characteristic),
            target: host
        )

        XCTAssertNotEqual(keyboard, mouse)
    }

    func testTheSameCharacteristicAndReportIDIsTheSameKeyForTheSameTarget() {
        let characteristic = NSObject()
        let host = UUID()

        let first = HIDPendingBroadcastKey(
            reportID: ReportID.keyboard.rawValue,
            characteristic: ObjectIdentifier(characteristic),
            target: host
        )
        let second = HIDPendingBroadcastKey(
            reportID: ReportID.keyboard.rawValue,
            characteristic: ObjectIdentifier(characteristic),
            target: host
        )

        XCTAssertEqual(first, second)
    }

    func testTheSameCharacteristicAndReportIDForDifferentTargetsIsADifferentKey() {
        let characteristic = NSObject()
        let oldHost = UUID()
        let newHost = UUID()

        let oldRelease = HIDPendingBroadcastKey(
            reportID: ReportID.keyboard.rawValue,
            characteristic: ObjectIdentifier(characteristic),
            target: oldHost
        )
        let newRelease = HIDPendingBroadcastKey(
            reportID: ReportID.keyboard.rawValue,
            characteristic: ObjectIdentifier(characteristic),
            target: newHost
        )

        XCTAssertNotEqual(oldRelease, newRelease)
        XCTAssertEqual(Set([oldRelease, newRelease]).count, 2)
    }

    /// The case behind the fix: switching control parks a release for the old host and then
    /// one for the new host on the same characteristic and report ID. Both slots have to
    /// exist at once, or the drain can only ever deliver one of the two zero reports.
    func testReleasesForTwoHostsCanBeParkedAtOnce() {
        let keyboardCharacteristic = NSObject()
        let oldHost = UUID()
        let newHost = UUID()

        let oldRelease = HIDPendingBroadcastKey(
            reportID: ReportID.keyboard.rawValue,
            characteristic: ObjectIdentifier(keyboardCharacteristic),
            target: oldHost
        )
        let newRelease = HIDPendingBroadcastKey(
            reportID: ReportID.keyboard.rawValue,
            characteristic: ObjectIdentifier(keyboardCharacteristic),
            target: newHost
        )
        let parked = [oldRelease: "old host release", newRelease: "new host release"]

        XCTAssertEqual(parked.count, 2)
        XCTAssertEqual(parked[oldRelease], "old host release")
        XCTAssertEqual(parked[newRelease], "new host release")
    }
}
