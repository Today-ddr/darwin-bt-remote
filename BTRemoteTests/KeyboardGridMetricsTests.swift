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

    /// A stacked cell is two touch bands that meet at the middle: together they cover
    /// the cell edge to edge, so there is no dead strip between Up and Down.
    func testStackedCellTouchBandsTileTheWholeCell() {
        let cellHeight: CGFloat = 24
        let sut = StackedKeyCellGeometry(cellHeight: cellHeight, gap: FullKeyboardLayoutPolicy.keyGap)
        let top = sut.topTouchFrame(width: 40)
        let bottom = sut.bottomTouchFrame(width: 40)

        XCTAssertEqual(top.minY, 0, accuracy: 0.001)
        XCTAssertEqual(top.maxY, cellHeight / 2, accuracy: 0.001)
        XCTAssertEqual(bottom.minY, top.maxY, accuracy: 0.001)
        XCTAssertEqual(bottom.maxY, cellHeight, accuracy: 0.001)
        XCTAssertEqual(top.height + bottom.height, cellHeight, accuracy: 0.001)
    }

    /// The caps inside those bands stay where they were: each is pulled back from the
    /// shared middle edge by half the row gap, so the drawn key gap is unchanged.
    func testStackedCellCapsKeepTheVisualGap() {
        let cellHeight: CGFloat = 24
        let gap = FullKeyboardLayoutPolicy.keyGap
        let sut = StackedKeyCellGeometry(cellHeight: cellHeight, gap: gap)
        let top = sut.topCapFrame(width: 40)
        let bottom = sut.bottomCapFrame(width: 40)

        XCTAssertEqual(top.minY, 0, accuracy: 0.001)
        XCTAssertEqual(bottom.maxY, cellHeight, accuracy: 0.001)
        XCTAssertEqual(top.height, (cellHeight - gap) / 2, accuracy: 0.001)
        XCTAssertEqual(bottom.height, top.height, accuracy: 0.001)
        XCTAssertEqual(bottom.minY - top.maxY, gap, accuracy: 0.001)
    }
}
