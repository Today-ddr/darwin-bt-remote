@testable import BTRemote
import XCTest

final class DockVisibilityPolicyTests: XCTestCase {
    func testPortraitSetupShowsDock() {
        XCTAssertTrue(
            DockVisibilityPolicy.showsDock(isLandscape: false, selectedTab: .setup)
        )
    }

    func testPortraitSettingsShowsDock() {
        XCTAssertTrue(
            DockVisibilityPolicy.showsDock(isLandscape: false, selectedTab: .settings)
        )
    }

    func testPortraitInputKeepsDockHiddenDuringTransition() {
        XCTAssertFalse(
            DockVisibilityPolicy.showsDock(isLandscape: false, selectedTab: .input)
        )
    }

    func testLandscapeHidesDockOnEveryTab() {
        XCTAssertFalse(
            DockVisibilityPolicy.showsDock(isLandscape: true, selectedTab: .setup)
        )
        XCTAssertFalse(
            DockVisibilityPolicy.showsDock(isLandscape: true, selectedTab: .input)
        )
        XCTAssertFalse(
            DockVisibilityPolicy.showsDock(isLandscape: true, selectedTab: .settings)
        )
    }
}
