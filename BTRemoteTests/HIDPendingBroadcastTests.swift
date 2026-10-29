@testable import BTRemote
import XCTest

/// The parked-report key has to distinguish two characteristics that carry the same report
/// ID: the main keyboard report and the boot keyboard report are both Report ID 2 on UUID
/// 0x2A4D, and keying only by ID let one overwrite the other's key-up. These use plain
/// objects for identity — the key is `ObjectIdentifier`-based, so CoreBluetooth is not
/// needed to prove the property.
final class HIDPendingBroadcastTests: XCTestCase {
    func testTheSameReportIDOnDifferentCharacteristicsIsADifferentKey() {
        let mainKeyboardReport = NSObject()
        let bootKeyboardReport = NSObject()

        let main = HIDPendingBroadcastKey(
            reportID: ReportID.keyboard.rawValue,
            characteristic: ObjectIdentifier(mainKeyboardReport)
        )
        let boot = HIDPendingBroadcastKey(
            reportID: ReportID.keyboard.rawValue,
            characteristic: ObjectIdentifier(bootKeyboardReport)
        )

        XCTAssertNotEqual(main, boot)
        XCTAssertEqual(Set([main, boot]).count, 2)
    }

    func testDifferentReportIDsOnOneCharacteristicAreDifferentKeys() {
        let characteristic = NSObject()

        let keyboard = HIDPendingBroadcastKey(
            reportID: ReportID.keyboard.rawValue,
            characteristic: ObjectIdentifier(characteristic)
        )
        let mouse = HIDPendingBroadcastKey(
            reportID: ReportID.mouse.rawValue,
            characteristic: ObjectIdentifier(characteristic)
        )

        XCTAssertNotEqual(keyboard, mouse)
    }

    func testTheSameCharacteristicAndReportIDIsTheSameKey() {
        let characteristic = NSObject()

        let first = HIDPendingBroadcastKey(
            reportID: ReportID.keyboard.rawValue,
            characteristic: ObjectIdentifier(characteristic)
        )
        let second = HIDPendingBroadcastKey(
            reportID: ReportID.keyboard.rawValue,
            characteristic: ObjectIdentifier(characteristic)
        )

        XCTAssertEqual(first, second)
    }
}
