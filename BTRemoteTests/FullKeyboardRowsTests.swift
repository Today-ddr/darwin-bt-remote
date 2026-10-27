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

    func testMainRowsUseStandardModifierWidths() throws {
        let sut = FullKeyboardView()
        let enter = try XCTUnwrap(sut.row3.last)
        let leftShift = try XCTUnwrap(sut.row4.first)
        let rightShift = try XCTUnwrap(sut.row4.last)

        XCTAssertEqual(sut.row3[0].weight, 1.75, accuracy: 0.001)
        XCTAssertEqual(enter.weight, 2.25, accuracy: 0.001)
        XCTAssertEqual(leftShift.weight, 2.25, accuracy: 0.001)
        XCTAssertEqual(rightShift.weight, 1.75, accuracy: 0.001)
    }

    func testBottomRowUsesAppleModifierOrder() {
        let sut = FullKeyboardView()
        let modifiers = sut.row5.compactMap { key -> KeyboardModifiers? in
            guard case let .modifier(mod) = key.action else { return nil }
            return mod
        }

        XCTAssertEqual(
            modifiers,
            [.leftCtrl, .leftAlt, .leftGUI, .rightGUI, .rightAlt]
        )
    }

    func testBottomRowUsesTheFullTrailingEdge() {
        let sut = FullKeyboardView()
        let trailing = sut.row5.suffix(3)

        XCTAssertEqual(trailing.map(\.weight), [1.0, 1.0, 1.75])
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
