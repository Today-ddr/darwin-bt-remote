@testable import BTRemote
import XCTest

@MainActor
final class ScrollStepTests: XCTestCase {
    func testTheStepNeverCollapsesToZero() {
        XCTAssertEqual(ScrollStep.amount(scrollSensitivity: 0), 1)
        XCTAssertEqual(ScrollStep.amount(scrollSensitivity: 0.5), 1)
        XCTAssertEqual(ScrollStep.amount(scrollSensitivity: 1), 3)
        XCTAssertEqual(ScrollStep.amount(scrollSensitivity: 3), 9)
    }

    func testUpIsPositiveAndDownIsNegative() {
        XCTAssertEqual(
            ScrollStep.wheel(direction: 1, scrollSensitivity: 1, invertScroll: false),
            3
        )
        XCTAssertEqual(
            ScrollStep.wheel(direction: -1, scrollSensitivity: 1, invertScroll: false),
            -3
        )
    }

    func testInvertedScrollingFlipsBothDirections() {
        XCTAssertEqual(
            ScrollStep.wheel(direction: 1, scrollSensitivity: 1, invertScroll: true),
            -3
        )
        XCTAssertEqual(
            ScrollStep.wheel(direction: -1, scrollSensitivity: 1, invertScroll: true),
            3
        )
    }

    func testTheScrollButtonPathSendsOneWheelReportAndNoZeroBehindIt() {
        var reports: [MouseReport] = []
        let hid = makeHID { reports.append($0) }

        hid.scroll(ScrollStep.wheel(direction: 1, scrollSensitivity: 1, invertScroll: false))

        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(reports.first?.wheel, 3)
        XCTAssertEqual(reports.first?.buttons, MouseButtons())
    }

    func testZeroWheelSendsNothing() {
        var reports: [MouseReport] = []
        let hid = makeHID { reports.append($0) }

        hid.scroll(0)

        XCTAssertTrue(reports.isEmpty)
    }

    func testAClickIsAPressFollowedByOneRelease() {
        var reports: [MouseReport] = []
        let hid = makeHID { reports.append($0) }

        hid.click(.left)

        XCTAssertEqual(reports.map(\.buttons), [[.left], []])
        XCTAssertEqual(reports.count, 2)
    }

    private func makeHID(_ record: @escaping (MouseReport) -> Void) -> HIDInput {
        HIDInput(
            sendMouse: record,
            sendKeyboard: { _ in },
            updateBattery: { _ in },
            isActive: true,
            isConnected: true,
            activeError: nil,
            batteryLevel: 100,
            isCapsLockOn: false
        )
    }
}
