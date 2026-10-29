@testable import BTRemote
import UIKit
import XCTest

final class AppOrientationPolicyTests: XCTestCase {
    func testInputAllowsLandscapeOnly() {
        XCTAssertEqual(AppOrientationPolicy.mask(for: .input), .landscape)
    }

    func testSetupAllowsEveryOrientation() {
        XCTAssertEqual(AppOrientationPolicy.mask(for: .setup), .all)
    }

    func testSettingsAllowsEveryOrientation() {
        XCTAssertEqual(AppOrientationPolicy.mask(for: .settings), .all)
    }
}
