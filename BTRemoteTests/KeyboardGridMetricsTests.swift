@testable import BTRemote
import CoreGraphics
import XCTest

final class KeyboardGridMetricsTests: XCTestCase {
    func testGridUsesFourteenPointFiveUnits() {
        XCTAssertEqual(KeyboardGridMetrics.totalUnits, 14.5)
    }

    func testOneUnitKeysUseTheSamePitchInEveryRow() {
        let sut = KeyboardGridMetrics(width: 600, gap: 5)

        let grave = sut.frame(startUnits: 0, widthUnits: 1, height: 44)
        let digit1 = sut.frame(startUnits: 1, widthUnits: 1, height: 44)
        let q = sut.frame(startUnits: 1.5, widthUnits: 1, height: 44)

        XCTAssertEqual(grave.minX, 2.5, accuracy: 0.001)
        XCTAssertEqual(digit1.minX, 43.879, accuracy: 0.001)
        XCTAssertEqual(q.minX, 64.569, accuracy: 0.001)
        XCTAssertEqual(digit1.width, 36.379, accuracy: 0.001)
        XCTAssertEqual(q.width, 36.379, accuracy: 0.001)
    }

    func testFourteenPointFiveUnitRowFillsWidthWithSymmetricHalfGaps() {
        let sut = KeyboardGridMetrics(width: 600, gap: 5)
        let first = sut.frame(startUnits: 0, widthUnits: 1, height: 44)
        let last = sut.frame(startUnits: 13.5, widthUnits: 1, height: 44)

        XCTAssertEqual(first.minX, 2.5, accuracy: 0.001)
        XCTAssertEqual(last.maxX, 597.5, accuracy: 0.001)
    }

    func testFourPointGapUsesTheSharedKeySpacing() {
        let sut = KeyboardGridMetrics(width: 600, gap: FullKeyboardLayoutPolicy.keyGap)
        let key = sut.frame(startUnits: 0, widthUnits: 1, height: 44)

        XCTAssertEqual(key.width, 37.379, accuracy: 0.001)
    }

    func testZeroWidthDoesNotProduceNegativeFrames() {
        let sut = KeyboardGridMetrics(width: 0, gap: 5)
        let frame = sut.frame(startUnits: 0, widthUnits: 1, height: 44)

        XCTAssertEqual(sut.unitWidth, 0)
        XCTAssertEqual(frame.width, 0)
    }
}
