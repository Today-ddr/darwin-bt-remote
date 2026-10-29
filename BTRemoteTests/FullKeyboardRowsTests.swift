@testable import BTRemote
import CoreGraphics
import XCTest

@MainActor
final class FullKeyboardRowsTests: XCTestCase {
    private let totalUnits = KeyboardGridMetrics.totalUnits
    private let functionKeyWidth = (KeyboardGridMetrics.totalUnits - 1.5) / 12
    private let allArrowCodes: Set<Keycode> = [.leftArrow, .upArrow, .downArrow, .rightArrow]

    func testEveryRowUsesFourteenPointFiveUnits() {
        let sut = makeSUT()
        let rows = [sut.row0, sut.row1, sut.row2, sut.row3, sut.row4, sut.row5]

        for (index, row) in rows.enumerated() {
            let total = row.reduce(CGFloat.zero) { $0 + $1.weight }
            XCTAssertEqual(total, totalUnits, accuracy: 0.001, "row \(index)")
        }
    }

    func testRowCellCountsMatchMacBookGeometry() {
        let sut = makeSUT()

        XCTAssertEqual(sut.row0.count, 13)
        XCTAssertEqual(sut.row1.count, 14)
        XCTAssertEqual(sut.row2.count, 14)
        XCTAssertEqual(sut.row3.count, 13)
        XCTAssertEqual(sut.row4.count, 12)
        XCTAssertEqual(sut.row5.count, 9)
    }

    func testFunctionRowHasThirteenKeysWithAWiderEscape() {
        let sut = makeSUT()
        let functionRow = sut.row0

        XCTAssertEqual(functionRow.count, 13)
        XCTAssertEqual(functionRow.first?.weight ?? 0, 1.5, accuracy: 0.001)
        for key in functionRow.dropFirst() {
            XCTAssertEqual(key.weight, functionKeyWidth, accuracy: 0.001)
        }
        let total = functionRow.reduce(CGFloat.zero) { $0 + $1.weight }
        XCTAssertEqual(total, totalUnits, accuracy: 0.001)
    }

    func testFunctionRowExcludesPrintScreenAndForwardDelete() {
        let sut = makeSUT()

        XCTAssertFalse(
            sut.row0.contains { key in
                if case let .key(code) = key.action {
                    return code == .printScreen || code == .deleteForward
                }
                return false
            }
        )
    }

    func testFunctionRowKeepsEscapeAndAllTwelveFunctionKeys() {
        let sut = makeSUT()
        let codes = sut.row0.compactMap { key -> Keycode? in
            guard case let .key(code) = key.action else { return nil }
            return code
        }
        let expected: [Keycode] = [
            .escape, .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12
        ]

        XCTAssertEqual(codes, expected)
    }

    func testMainRowsUseMacBookModifierWidths() throws {
        let sut = makeSUT()

        XCTAssertEqual(try XCTUnwrap(sut.row1.last).weight, 1.5, accuracy: 0.001, "Backspace")
        XCTAssertEqual(try XCTUnwrap(sut.row2.first).weight, 1.5, accuracy: 0.001, "Tab")
        XCTAssertEqual(try XCTUnwrap(sut.row2.last).weight, 1.0, accuracy: 0.001, "backslash")
        XCTAssertEqual(try XCTUnwrap(sut.row3.first).weight, 1.75, accuracy: 0.001, "Caps Lock")
        XCTAssertEqual(try XCTUnwrap(sut.row3.last).weight, 1.75, accuracy: 0.001, "Return")
        XCTAssertEqual(try XCTUnwrap(sut.row4.first).weight, 2.25, accuracy: 0.001, "left Shift")
        XCTAssertEqual(try XCTUnwrap(sut.row4.last).weight, 2.25, accuracy: 0.001, "right Shift")
    }

    func testBottomRowUsesAppleModifierOrder() {
        let sut = makeSUT()
        let modifiers = sut.row5.compactMap { key -> KeyboardModifiers? in
            guard case let .modifier(mod) = key.action else { return nil }
            return mod
        }

        XCTAssertEqual(
            modifiers,
            [.leftCtrl, .leftAlt, .leftGUI, .rightGUI, .rightAlt]
        )
    }

    func testBottomRowMatchesMacBookColumnWidths() {
        let sut = makeSUT()

        XCTAssertEqual(sut.row5.map(\.weight), [1.0, 1.0, 1.25, 6.0, 1.25, 1.0, 1.0, 1.0, 1.0])
    }

    func testBottomRowHasNoFnOrGlobeKey() throws {
        let sut = makeSUT()
        let first = try XCTUnwrap(sut.row5.first)

        guard case let .modifier(firstModifier) = first.action else {
            return XCTFail("the bottom row must start with a modifier")
        }
        XCTAssertEqual(firstModifier, .leftCtrl)

        for key in sut.row5 {
            assertNoFnOrGlobe(key.label, "row5 cap")
            guard let below = key.stackedBelow else { continue }
            assertNoFnOrGlobe(below.label, "row5 stackedBelow cap")
            guard case let .key(code) = below.action else {
                return XCTFail("the stacked half must be a key, not a modifier")
            }
            XCTAssertEqual(code, .downArrow, "only Down may be hidden in a stacked cell")
        }
        XCTAssertEqual(modifiers(in: sut.row5).count, 5)
    }

    func testUpArrowIsNotOnTheShiftRow() {
        let sut = makeSUT()

        XCTAssertNil(index(of: .upArrow, in: sut.row4))
        XCTAssertEqual(sut.row4.count, 12)
    }

    func testArrowClusterUsesThreeEqualWidthColumnsForFourArrows() throws {
        let sut = makeSUT()
        let left = try XCTUnwrap(index(of: .leftArrow, in: sut.row5))
        let right = try XCTUnwrap(index(of: .rightArrow, in: sut.row5))

        XCTAssertEqual(right, left + 2, "Left and Right must be separated by the stacked Up/Down column")
        XCTAssertEqual(sut.row5[left].weight, 1.0, accuracy: 0.001)
        XCTAssertEqual(sut.row5[left + 1].weight, 1.0, accuracy: 0.001)
        XCTAssertEqual(sut.row5[right].weight, 1.0, accuracy: 0.001)
        XCTAssertNotNil(sut.row5[left + 1].stackedBelow, "the middle column must carry both Up and Down")
        XCTAssertEqual(arrowKeycodes(in: sut.row5), [.leftArrow, .upArrow, .downArrow, .rightArrow])
    }

    func testUpAndDownShareOneStackedCellWithIndependentActions() throws {
        let sut = makeSUT()

        XCTAssertNil(index(of: .downArrow, in: sut.row5), "Down must not be its own cell")
        XCTAssertNil(index(of: .upArrow, in: sut.row4), "Up must not be on the shift row")

        let pairIndex = try XCTUnwrap(index(of: .upArrow, in: sut.row5))
        let pair = sut.row5[pairIndex]
        XCTAssertEqual(pair.weight, 1.0, accuracy: 0.001)

        guard case let .key(upCode) = pair.action else {
            return XCTFail("the stacked cell's top cap must be a key")
        }
        XCTAssertEqual(upCode, .upArrow)

        let down = try XCTUnwrap(pair.stackedBelow, "Up must carry Down in the same cell")
        guard case let .key(downCode) = down.action else {
            return XCTFail("the stacked cell's bottom cap must be a key")
        }

        XCTAssertEqual(downCode, .downArrow)
        XCTAssertNotEqual(upCode, downCode)
    }

    private func makeSUT() -> FullKeyboardView {
        FullKeyboardView(releases: InputReleaseCoordinator())
    }

    private func index(of code: Keycode, in row: [FullKeyCap]) -> Int? {
        row.firstIndex { key in
            guard case let .key(candidate) = key.action else { return false }
            return candidate == code
        }
    }

    private func modifiers(in row: [FullKeyCap]) -> [KeyboardModifiers] {
        row.compactMap { key in
            guard case let .modifier(mod) = key.action else { return nil }
            return mod
        }
    }

    /// Every arrow the row answers, including one stacked inside another cell, in
    /// grid order. Four arrows sit in three columns: Left, Up/Down, Right.
    private func arrowKeycodes(in row: [FullKeyCap]) -> [Keycode] {
        row.flatMap { key -> [Keycode] in
            var codes: [Keycode] = []
            if case let .key(code) = key.action, allArrowCodes.contains(code) {
                codes.append(code)
            }
            if let below = key.stackedBelow,
               case let .key(code) = below.action,
               allArrowCodes.contains(code)
            {
                codes.append(code)
            }
            return codes
        }
    }

    private func assertNoFnOrGlobe(_ label: FullKeyCap.Label, _ context: String) {
        let text = labelText(label).lowercased()
        XCTAssertFalse(text.contains("fn"), "unexpected Fn key on \(context): \(text)")
        XCTAssertFalse(text.contains("globe"), "unexpected Globe key on \(context): \(text)")
    }

    private func labelText(_ label: FullKeyCap.Label) -> String {
        switch label {
        case let .text(text):
            text
        case let .letter(letter):
            letter
        case let .dual(top, bottom):
            top + bottom
        case let .symbol(symbol, fallback):
            symbol + fallback
        case .capsLock:
            "caps"
        case let .modifier(name, symbol, _):
            name + symbol
        }
    }
}
