@testable import BTRemote
import CoreGraphics
import XCTest

final class FullKeyboardLayoutPolicyTests: XCTestCase {
    func testLandscapeWithSafeAreaUsesNoExtraKeyMargin() {
        XCTAssertEqual(FullKeyboardLayoutPolicy.keyGap, 4)
        XCTAssertEqual(
            FullKeyboardLayoutPolicy.keyHorizontalMargin(
                isLandscape: true,
                safeAreaInset: 59
            ),
            0
        )
        XCTAssertEqual(
            FullKeyboardLayoutPolicy.keyHorizontalMargin(
                isLandscape: true,
                safeAreaInset: 0
            ),
            8
        )
    }

    func testPortraitAndInsetFreeLandscapeKeepTheDefaultMargin() {
        XCTAssertEqual(
            FullKeyboardLayoutPolicy.keyHorizontalMargin(
                isLandscape: false,
                safeAreaInset: 59
            ),
            8
        )
        XCTAssertEqual(
            FullKeyboardLayoutPolicy.keyHorizontalMargin(
                isLandscape: true,
                safeAreaInset: 0
            ),
            8
        )
    }
}
