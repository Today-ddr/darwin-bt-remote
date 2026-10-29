@testable import BTRemote
import UIKit
import XCTest

final class AppOrientationPolicyTests: XCTestCase {
    func testInputAllowsLandscapeOnly() {
        XCTAssertEqual(AppOrientationPolicy.mask(for: .input), .landscape)
    }

    func testSetupAllowsPortraitOnly() {
        XCTAssertEqual(AppOrientationPolicy.mask(for: .setup), .portrait)
    }

    func testSettingsAllowsPortraitOnly() {
        XCTAssertEqual(AppOrientationPolicy.mask(for: .settings), .portrait)
    }
}
