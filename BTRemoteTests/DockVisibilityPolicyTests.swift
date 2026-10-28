@testable import BTRemote
import XCTest

final class DockVisibilityPolicyTests: XCTestCase {
    func testSettingOffAlwaysKeepsDock() {
        XCTAssertTrue(policy(hides: false, landscape: true, tab: .input, page: InputPage.keyboard.rawValue))
    }

    func testLandscapeKeyboardHidesDockWhenSettingIsOn() {
        XCTAssertFalse(policy(hides: true, landscape: true, tab: .input, page: InputPage.keyboard.rawValue))
    }

    func testPortraitKeepsDock() {
        XCTAssertTrue(policy(hides: true, landscape: false, tab: .input, page: InputPage.keyboard.rawValue))
    }

    func testTrackpadPageKeepsDock() {
        XCTAssertTrue(policy(hides: true, landscape: true, tab: .input, page: InputPage.trackpad.rawValue))
    }

    func testOtherTabsKeepDock() {
        XCTAssertTrue(policy(hides: true, landscape: true, tab: .setup, page: InputPage.keyboard.rawValue))
        XCTAssertTrue(policy(hides: true, landscape: true, tab: .settings, page: InputPage.keyboard.rawValue))
    }

    private func policy(
        hides: Bool,
        landscape: Bool,
        tab: AppTab,
        page: Int
    ) -> Bool {
        DockVisibilityPolicy.showsDock(
            hidesDockInLandscape: hides,
            isLandscape: landscape,
            selectedTab: tab,
            inputPageRawValue: page
        )
    }
}
