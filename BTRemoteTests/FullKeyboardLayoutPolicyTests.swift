@testable import BTRemote
import CoreGraphics
import XCTest

final class FullKeyboardLayoutPolicyTests: XCTestCase {
    func testPortraitStaysSingleColumn() {
        XCTAssertEqual(
            FullKeyboardLayoutPolicy.presentation(in: CGSize(width: 390, height: 844)),
            .singleColumn
        )
    }

    func testNarrowLandscapeStaysSingleColumn() {
        XCTAssertEqual(
            FullKeyboardLayoutPolicy.presentation(in: CGSize(width: 667, height: 375)),
            .singleColumn
        )
    }

    func testWidePhoneLandscapeGetsAReadableSidePanel() {
        guard case let .split(sidePanelWidth) =
            FullKeyboardLayoutPolicy.presentation(in: CGSize(width: 844, height: 390))
        else {
            return XCTFail("expected split layout")
        }
        XCTAssertEqual(sidePanelWidth, 227.88, accuracy: 0.01)
    }

    func testIPadLandscapeCapsTheSidePanel() {
        guard case let .split(sidePanelWidth) =
            FullKeyboardLayoutPolicy.presentation(in: CGSize(width: 1180, height: 820))
        else {
            return XCTFail("expected split layout")
        }
        XCTAssertEqual(sidePanelWidth, 300, accuracy: 0.01)
    }
}
