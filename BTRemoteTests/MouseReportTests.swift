@testable import BTRemote
import XCTest

final class MouseReportTests: XCTestCase {
    func testBootDataIsButtonsAndTwoAxesOnly() {
        let report = MouseReport(buttons: [.left, .middle], dX: 12, dY: -7, wheel: 3)

        XCTAssertEqual(report.data.count, 4)
        XCTAssertEqual(report.bootData.count, 3)
        XCTAssertEqual(
            Array(report.bootData),
            [
                MouseButtons.left.rawValue | MouseButtons.middle.rawValue,
                12,
                UInt8(bitPattern: -7)
            ]
        )
    }

    func testBootDataDoesNotCarryTheWheel() {
        let first = MouseReport(buttons: .right, dX: 1, dY: 2, wheel: 5)
        let second = MouseReport(buttons: .right, dX: 1, dY: 2, wheel: -5)

        XCTAssertNotEqual(first.data, second.data)
        XCTAssertEqual(first.bootData, second.bootData)
    }

    func testZeroBootDataIsAnEmptyThreeByteReport() {
        XCTAssertEqual(Array(MouseReport.zero.bootData), [0, 0, 0])
    }
}
