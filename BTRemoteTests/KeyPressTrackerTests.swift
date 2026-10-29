@testable import BTRemote
import XCTest

final class KeyPressTrackerTests: XCTestCase {
    func testASecondFingerOnTheSameKeyDoesNotReportAnotherPress() {
        var sut = KeyPressTracker<Keycode>()

        XCTAssertTrue(sut.press(.a))
        XCTAssertFalse(sut.press(.a))
        XCTAssertEqual(sut.heldKeys, [.a])
    }

    func testTheKeyIsReleasedOnlyWhenTheLastFingerLeaves() {
        var sut = KeyPressTracker<Keycode>()
        sut.press(.a)
        sut.press(.a)

        XCTAssertFalse(sut.release(.a))
        XCTAssertEqual(sut.heldKeys, [.a])
        XCTAssertTrue(sut.release(.a))
        XCTAssertTrue(sut.isEmpty)
    }

    func testReleasingAnUnheldKeyChangesNothing() {
        var sut = KeyPressTracker<Keycode>()

        XCTAssertFalse(sut.release(.a))
        XCTAssertTrue(sut.isEmpty)
    }

    func testDifferentKeysKeepIndependentCounts() {
        var sut = KeyPressTracker<Keycode>()
        sut.press(.b)
        sut.press(.a)

        XCTAssertTrue(sut.release(.a))
        XCTAssertEqual(sut.heldKeys, [.b])

        sut.press(.a)
        sut.release(.b)
        sut.release(.a)
        XCTAssertTrue(sut.isEmpty)
    }

    func testRemoveAllDropsEveryCount() {
        var sut = KeyPressTracker<Keycode>()
        sut.press(.a)
        sut.press(.a)
        sut.press(.b)

        sut.removeAll()

        XCTAssertTrue(sut.isEmpty)
        XCTAssertFalse(sut.release(.a))
    }

    func testTwoFingersOnTheSameModifierHoldItUntilTheLastOneLeaves() {
        var sut = KeyPressTracker<KeyboardModifiers>()

        XCTAssertTrue(sut.press(.leftShift))
        XCTAssertFalse(sut.press(.leftShift))
        XCTAssertEqual(sut.heldKeys, [.leftShift])

        XCTAssertFalse(sut.release(.leftShift))
        XCTAssertEqual(sut.heldKeys, [.leftShift])

        XCTAssertTrue(sut.release(.leftShift))
        XCTAssertTrue(sut.isEmpty)
    }

    func testTheTwoShiftKeysAreTrackedSeparately() {
        var sut = KeyPressTracker<KeyboardModifiers>()
        sut.press(.leftShift)
        sut.press(.rightShift)

        XCTAssertEqual(sut.heldKeys, [.leftShift, .rightShift])

        sut.release(.leftShift)
        XCTAssertEqual(sut.heldKeys, [.rightShift])
    }
}
