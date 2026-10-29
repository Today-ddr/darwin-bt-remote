@testable import BTRemote
import XCTest

final class HIDProfileTests: XCTestCase {
    func testReportMapOnlyCarriesKeyboardMouseAndLEDReports() {
        let map = Array(HIDProfile.reportMapData)
        let reportIDs = map.indices.compactMap { index -> UInt8? in
            guard map[index] == 0x85, index + 1 < map.count else { return nil }
            return map[index + 1]
        }

        XCTAssertEqual(reportIDs, [
            ReportID.keyboard.rawValue,
            ReportID.keyboardLEDs.rawValue,
            ReportID.mouse.rawValue
        ])
        XCTAssertFalse(reportIDs.contains(4))
        XCTAssertFalse(reportIDs.contains(5))
        XCTAssertFalse(reportIDs.contains(6))
        XCTAssertFalse(reportIDs.contains(7))
    }

    func testReportMapLengthMatchesItsParts() {
        // 61 bytes of keyboard + LED output, then 52 bytes of mouse
        XCTAssertEqual(HIDProfile.reportMapData.count, 113)
    }

    func testReportReferencesPointAtTheReportsThatStillExist() {
        XCTAssertEqual(Array(ReportID.keyboard.descriptor(.input)), [2, 1])
        XCTAssertEqual(Array(ReportID.keyboardLEDs.descriptor(.output)), [3, 2])
        XCTAssertEqual(Array(ReportID.mouse.descriptor(.input)), [1, 1])
    }
}
