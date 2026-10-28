@testable import BTRemote
import XCTest

final class KeyPressTrackerTests: XCTestCase {
    func testASecondFingerOnTheSameKeyDoesNotReportAnotherPress() {
        var sut = KeyPressTracker()

        XCTAssertTrue(sut.press(.a))
        XCTAssertFalse(sut.press(.a))
        XCTAssertEqual(sut.heldKeys, [.a])
    }

    func testTheKeyIsReleasedOnlyWhenTheLastFingerLeaves() {
        var sut = KeyPressTracker()
        sut.press(.a)
        sut.press(.a)

        XCTAssertFalse(sut.release(.a))
        XCTAssertEqual(sut.heldKeys, [.a])
        XCTAssertTrue(sut.release(.a))
        XCTAssertTrue(sut.isEmpty)
    }

    func testReleasingAnUnheldKeyChangesNothing() {
        var sut = KeyPressTracker()

        XCTAssertFalse(sut.release(.a))
        XCTAssertTrue(sut.isEmpty)
    }

    func testDifferentKeysKeepIndependentCounts() {
        var sut = KeyPressTracker()
        sut.press(.leftShift)
        sut.press(.a)

        XCTAssertFalse(sut.release(.a))
        XCTAssertEqual(sut.heldKeys, [.leftShift])

        sut.press(.a)
        sut.release(.leftShift)
        sut.release(.a)
        XCTAssertTrue(sut.isEmpty)
    }

    func testRemoveAllDropsEveryCount() {
        var sut = KeyPressTracker()
        sut.press(.a)
        sut.press(.a)
        sut.press(.b)

        sut.removeAll()

        XCTAssertTrue(sut.isEmpty)
        XCTAssertFalse(sut.release(.a))
    }
}
