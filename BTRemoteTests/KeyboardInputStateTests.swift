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

        let tap = sut.report(adding: .capsLock)

        XCTAssertEqual(tap.keys, [.a, .capsLock])
        XCTAssertEqual(tap.modifiers, [.leftShift])
        XCTAssertEqual(sut.report.keys, [.a])
        XCTAssertEqual(sut.report.modifiers, [.leftShift])
    }

    func testCapsLockTapDoesNotChangeHeldModifiers() {
        var sut = KeyboardInputState()
        sut.pressModifier(.leftGUI)
        sut.pressKey(.z)
        let heldBefore = sut.heldModifiers

        _ = sut.report(adding: .capsLock)

        XCTAssertEqual(sut.heldModifiers, heldBefore)
        XCTAssertEqual(sut.report.keys, [.z])
    }

    func testCapsLockNeverInjectsShiftIntoAShortcut() {
        var sut = KeyboardInputState()
        sut.pressModifier(.leftGUI)
        sut.pressKey(.z)

        let tap = sut.report(adding: .capsLock)
        XCTAssertFalse(tap.modifiers.contains(.leftShift))

        // Cmd+Z has to stay Cmd+Z: the host owns Caps Lock, and this report is
        // the one the host acts on.
        XCTAssertEqual(sut.report.modifiers, [.leftGUI])
        XCTAssertEqual(sut.report.keys, [.z])
        XCTAssertFalse(sut.isShiftActive)
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
