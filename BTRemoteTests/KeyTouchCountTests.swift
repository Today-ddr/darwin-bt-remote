@testable import BTRemote
import Combine
import XCTest

@MainActor
final class KeyTouchCountTests: XCTestCase {
    /// The count itself must not publish — it changes on every finger — and `isIdle`
    /// must publish only when the surface crosses zero: 0→1, 1→2, 2→1, 1→0.
    func testIsIdlePublishesOnlyOnTheZeroBoundary() {
        let sut = KeyTouchCount()
        var publishedIdle: [Bool] = []
        let cancellable = sut.$isIdle.dropFirst().sink { publishedIdle.append($0) }

        XCTAssertEqual(sut.value, 0)
        XCTAssertTrue(sut.isIdle)

        XCTAssertEqual(sut.touchDown(), 1)
        XCTAssertFalse(sut.isIdle)

        XCTAssertEqual(sut.touchDown(), 2)
        XCTAssertFalse(sut.isIdle)

        XCTAssertEqual(sut.touchUp(), 1)
        XCTAssertFalse(sut.isIdle)

        XCTAssertEqual(sut.touchUp(), 0)
        XCTAssertTrue(sut.isIdle)

        XCTAssertEqual(publishedIdle, [false, true])
        _ = cancellable
    }

    func testTheCountNeverGoesBelowZero() {
        let sut = KeyTouchCount()

        XCTAssertEqual(sut.touchUp(), 0)
        XCTAssertTrue(sut.isIdle)
    }
}
