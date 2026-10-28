@testable import BTRemote
import XCTest

final class KeyboardInputStateTests: XCTestCase {
    func testTwoFingersOnTheSameModifierHoldItUntilTheLastOneLeaves() {
        var sut = KeyboardInputState()

        XCTAssertTrue(sut.pressModifier(.leftShift))
        XCTAssertFalse(sut.pressModifier(.leftShift))
        XCTAssertEqual(sut.heldModifiers, [.leftShift])

        XCTAssertFalse(sut.releaseModifier(.leftShift))
        XCTAssertEqual(sut.heldModifiers, [.leftShift])

        XCTAssertTrue(sut.releaseModifier(.leftShift))
        XCTAssertEqual(sut.heldModifiers, [])
        XCTAssertTrue(sut.isEmpty)
    }

    func testModifierAndKeyProduceOneReport() {
        var sut = KeyboardInputState()
        sut.pressModifier(.leftShift)
        sut.pressKey(.a)

        let report = sut.report
        XCTAssertEqual(report.modifiers, [.leftShift])
        XCTAssertEqual(report.keys, [.a])

        sut.releaseKey(.a)
        sut.releaseModifier(.leftShift)
        XCTAssertEqual(sut.report, .zero)
    }

    func testEveryHeldModifierIsUnionedIntoTheReport() {
        var sut = KeyboardInputState()
        sut.pressModifier(.leftShift)
        sut.pressModifier(.leftGUI)
        sut.pressKey(.a)

        XCTAssertEqual(sut.report.modifiers, [.leftShift, .leftGUI])

        sut.releaseModifier(.leftGUI)
        XCTAssertEqual(sut.report.modifiers, [.leftShift])
    }

    func testCapsLockTapCarriesTheHeldStateAndThenTheHeldReport() {
        var sut = KeyboardInputState()
        sut.pressKey(.a)
        sut.pressModifier(.leftShift)

        sut.toggleCapsLock()

        XCTAssertTrue(sut.isCapsLockOn)
        XCTAssertEqual(sut.report(adding: .capsLock).keys, [.a, .capsLock])
        XCTAssertEqual(sut.report(adding: .capsLock).modifiers, [.leftShift])
        XCTAssertEqual(sut.report.keys, [.a])
        XCTAssertEqual(sut.report.modifiers, [.leftShift])
    }

    func testCapsLockFoldsShiftOnlyOverHeldLetters() {
        var sut = KeyboardInputState()
        sut.toggleCapsLock()

        XCTAssertEqual(sut.report.modifiers, [])

        sut.pressKey(.a)
        XCTAssertEqual(sut.report.modifiers, [.leftShift])

        sut.pressKey(.digit1)
        XCTAssertEqual(sut.report.modifiers, [.leftShift])

        sut.releaseKey(.a)
        XCTAssertEqual(sut.report.modifiers, [])
    }

    func testReleaseEverythingClearsKeysAndModifiersOnce() {
        var sut = KeyboardInputState()
        sut.pressKey(.a)
        sut.pressModifier(.leftCtrl)

        XCTAssertTrue(sut.releaseEverything())
        XCTAssertTrue(sut.isEmpty)
        XCTAssertEqual(sut.heldModifiers, [])
        XCTAssertEqual(sut.report, .zero)

        XCTAssertFalse(sut.releaseEverything())
    }
}
