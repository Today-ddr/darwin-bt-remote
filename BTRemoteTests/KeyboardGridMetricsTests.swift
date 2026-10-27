import CoreGraphics
import XCTest
@testable import BTRemote

final class KeyboardGridMetricsTests: XCTestCase {
    func testOneUnitKeysUseTheSamePitchInEveryRow() {
        let sut = KeyboardGridMetrics(width: 600, gap: 5)

        let grave = sut.frame(startUnits: 0, widthUnits: 1, height: 44)
        let digit1 = sut.frame(startUnits: 1, widthUnits: 1, height: 44)
        let q = sut.frame(startUnits: 1.5, widthUnits: 1, height: 44)

        XCTAssertEqual(grave.minX, 2.5, accuracy: 0.001)
        XCTAssertEqual(digit1.minX, 42.5, accuracy: 0.001)
        XCTAssertEqual(q.minX, 62.5, accuracy: 0.001)
        XCTAssertEqual(digit1.width, 35, accuracy: 0.001)
        XCTAssertEqual(q.width, 35, accuracy: 0.001)
    }

    func testFifteenUnitRowFillsWidthWithSymmetricHalfGaps() {
        let sut = KeyboardGridMetrics(width: 600, gap: 5)
        let first = sut.frame(startUnits: 0, widthUnits: 1, height: 44)
        let last = sut.frame(startUnits: 14, widthUnits: 1, height: 44)

        XCTAssertEqual(first.minX, 2.5, accuracy: 0.001)
        XCTAssertEqual(last.maxX, 597.5, accuracy: 0.001)
    }

    func testZeroWidthDoesNotProduceNegativeFrames() {
        let sut = KeyboardGridMetrics(width: 0, gap: 5)
        let frame = sut.frame(startUnits: 0, widthUnits: 1, height: 44)

        XCTAssertEqual(sut.unitWidth, 0)
        XCTAssertEqual(frame.width, 0)
    }
}
