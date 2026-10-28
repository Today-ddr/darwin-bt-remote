@testable import BTRemote
import XCTest

final class HapticsDefaultsTests: XCTestCase {
    func testMissingIntensityDefaultsToMedium() {
        XCTAssertEqual(Haptics.Intensity.from(nil), .medium)
        XCTAssertEqual(Haptics.Intensity.from(""), .medium)
    }

    func testUnknownIntensityFallsBackToMedium() {
        XCTAssertEqual(Haptics.Intensity.from("future-level"), .medium)
    }

    func testStoredIntensitiesStillResolve() {
        XCTAssertEqual(Haptics.Intensity.from("light"), .light)
        XCTAssertEqual(Haptics.Intensity.from("medium"), .medium)
        XCTAssertEqual(Haptics.Intensity.from("strong"), .strong)
    }
}
