@testable import BTRemote
import SwiftUI
import XCTest

final class AppThemeTests: XCTestCase {
    func testUnknownStoredValueFallsBackToSystem() {
        XCTAssertEqual(AppTheme(storedValue: "future-theme"), .system)
    }

    func testExistingStoredValuesStillResolve() {
        XCTAssertEqual(AppTheme(storedValue: "system"), .system)
        XCTAssertEqual(AppTheme(storedValue: "light"), .light)
        XCTAssertEqual(AppTheme(storedValue: "dark"), .dark)
    }

    func testOLEDForcesDarkAndUsesPureBlackSurface() {
        XCTAssertEqual(AppTheme.oled.preferredColorScheme, .dark)
        XCTAssertTrue(AppTheme.oled.usesPureBlackSurface)
    }

    func testStandardThemesDoNotUsePureBlackSurface() {
        XCTAssertFalse(AppTheme.system.usesPureBlackSurface)
        XCTAssertFalse(AppTheme.light.usesPureBlackSurface)
        XCTAssertFalse(AppTheme.dark.usesPureBlackSurface)
    }
}
