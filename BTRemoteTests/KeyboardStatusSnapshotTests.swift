@testable import BTRemote
import XCTest

final class KeyboardStatusSnapshotTests: XCTestCase {
    func testErrorTakesPriorityOverConnection() {
        let status = snapshot(connected: true, error: "dropped")

        XCTAssertEqual(status.kind, .error)
        XCTAssertEqual(status.accessibilityValue, "dropped")
    }

    func testConnectedStateShowsAtLeastOneHost() {
        let status = snapshot(connected: true, count: 0)

        XCTAssertEqual(status.kind, .connected)
        XCTAssertEqual(status.connectedCountText, "1")
    }

    func testActiveWithoutAConnectionIsReady() {
        let status = snapshot(active: true)

        XCTAssertEqual(status.kind, .ready)
        XCTAssertNil(status.connectedCountText)
    }

    func testInactiveStateHasNoCount() {
        let status = snapshot()

        XCTAssertEqual(status.kind, .inactive)
        XCTAssertNil(status.connectedCountText)
    }

    func testCapsLockGlyphTakesPriorityOverShift() {
        let status = KeyboardStatusSnapshot(
            isActive: true,
            isConnected: true,
            connectedHostCount: 1,
            errorMessage: nil,
            isCapsLockOn: true,
            isShiftActive: true
        )

        XCTAssertEqual(status.modifierGlyph, "⇪")
    }

    private func snapshot(
        active: Bool = false,
        connected: Bool = false,
        count: Int = 0,
        error: String? = nil
    ) -> KeyboardStatusSnapshot {
        KeyboardStatusSnapshot(
            isActive: active,
            isConnected: connected,
            connectedHostCount: count,
            errorMessage: error,
            isCapsLockOn: false,
            isShiftActive: false
        )
    }
}
