@testable import BTRemote
import CoreGraphics
import XCTest

@MainActor
final class FullKeyboardRowsTests: XCTestCase {
    func testEveryRowUsesFifteenUnits() {
        let sut = FullKeyboardView()
        let rows = [sut.row0, sut.row1, sut.row2, sut.row3, sut.row4, sut.row5]

        for (index, row) in rows.enumerated() {
            let total = row.reduce(CGFloat.zero) { $0 + $1.weight }
            XCTAssertEqual(total, 15, accuracy: 0.001, "row \(index)")
        }
    }

    func testUpArrowSitsExactlyAboveDownArrow() {
        let sut = FullKeyboardView()
        let up = key(.upArrow, in: sut.row4)
        let down = key(.downArrow, in: sut.row5)
        let upStart = startUnits(before: up.index, in: sut.row4)
        let downStart = startUnits(before: down.index, in: sut.row5)

        XCTAssertEqual(upStart, downStart, accuracy: 0.001)
        XCTAssertEqual(up.key.weight, down.key.weight, accuracy: 0.001)
    }

    private func key(
        _ code: Keycode,
        in row: [FullKeyCap]
    ) -> (index: Int, key: FullKeyCap) {
        guard let index = row.firstIndex(where: { key in
            if case let .key(candidate) = key.action {
                return candidate == code
            }
            return false
        }) else {
            XCTFail("missing key \(code)")
            return (-1, row[0])
        }
        return (index, row[index])
    }

    private func startUnits(before index: Int, in row: [FullKeyCap]) -> CGFloat {
        row.prefix(index).reduce(CGFloat.zero) { $0 + $1.weight }
    }
}
