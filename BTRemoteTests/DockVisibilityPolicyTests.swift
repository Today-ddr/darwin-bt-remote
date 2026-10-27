@testable import BTRemote
import XCTest

final class DockVisibilityPolicyTests: XCTestCase {
    func testSettingOffAlwaysKeepsDock() {
        XCTAssertTrue(policy(hides: false, landscape: true, tab: .remote, page: 0))
    }

    func testLandscapeComboHidesDockWhenSettingIsOn() {
        XCTAssertFalse(policy(hides: true, landscape: true, tab: .remote, page: 0))
    }

    func testPortraitKeepsDock() {
        XCTAssertTrue(policy(hides: true, landscape: false, tab: .remote, page: 0))
    }

    func testOtherKeyboardPageKeepsDock() {
        XCTAssertTrue(policy(hides: true, landscape: true, tab: .remote, page: 1))
        XCTAssertTrue(policy(hides: true, landscape: true, tab: .remote, page: 2))
    }

    func testRemoteModeAndOtherTabsKeepDock() {
        XCTAssertTrue(
            DockVisibilityPolicy.showsDock(
                hidesDockInLandscape: true,
                isLandscape: true,
                selectedTab: .remote,
                remoteMode: .remote,
                keyboardPageRawValue: 0
            )
        )
        XCTAssertTrue(policy(hides: true, landscape: true, tab: .setup, page: 0))
        XCTAssertTrue(policy(hides: true, landscape: true, tab: .settings, page: 0))
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
            remoteMode: .keyboard,
            keyboardPageRawValue: page
        )
    }
}
