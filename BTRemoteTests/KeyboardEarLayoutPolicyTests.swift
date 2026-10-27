@testable import BTRemote
import CoreGraphics
import XCTest

final class KeyboardEarLayoutPolicyTests: XCTestCase {
    func testIPhone15ProLandscapeShowsBadgesAndCentersThemInTheEars() {
        let size = CGSize(width: 852, height: 393)

        XCTAssertTrue(KeyboardEarLayoutPolicy.showsBadge(in: size, earWidth: 59))
        XCTAssertEqual(
            KeyboardEarLayoutPolicy.badgePadding(for: 59),
            10.5,
            accuracy: 0.001
        )
    }

    func testPortraitHidesEarBadges() {
        XCTAssertFalse(
            KeyboardEarLayoutPolicy.showsBadge(
                in: CGSize(width: 393, height: 852),
                earWidth: 59
            )
        )
    }

    func testNarrowLandscapeEarHidesBadge() {
        XCTAssertFalse(
            KeyboardEarLayoutPolicy.showsBadge(
                in: CGSize(width: 667, height: 375),
                earWidth: 20
            )
        )
    }
}
