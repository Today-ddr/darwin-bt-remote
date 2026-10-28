@testable import BTRemote
import XCTest

@MainActor
final class TrackpadInteractionPolicyTests: XCTestCase {
    func testLongPressUsesTheAgreedDurationAndMovementAllowance() {
        XCTAssertEqual(LongPressDragPolicy.minimumPressDuration, 0.35, accuracy: 0.0001)
        XCTAssertEqual(LongPressDragPolicy.allowableMovement, 8, accuracy: 0.0001)
    }

    func testLongPressRequiresExactlyOneTouch() {
        XCTAssertTrue(LongPressDragPolicy.canBegin(isEnabled: true, isDragging: false, touchCount: 1))
        XCTAssertFalse(LongPressDragPolicy.canBegin(isEnabled: true, isDragging: false, touchCount: 0))
        XCTAssertFalse(LongPressDragPolicy.canBegin(isEnabled: true, isDragging: false, touchCount: 2))
    }

    func testLongPressNeedsTheSettingAndNoLiveDrag() {
        XCTAssertFalse(LongPressDragPolicy.canBegin(isEnabled: false, isDragging: false, touchCount: 1))
        XCTAssertFalse(LongPressDragPolicy.canBegin(isEnabled: true, isDragging: true, touchCount: 1))
    }

    func testASecondTouchCancelsThePress() {
        XCTAssertFalse(LongPressDragPolicy.cancels(touchCount: 1))
        XCTAssertTrue(LongPressDragPolicy.cancels(touchCount: 2))
    }

    func testDragStartsOnceAndEndsOnce() {
        var sut = TrackpadDragState()

        XCTAssertTrue(sut.begin())
        XCTAssertFalse(sut.begin())
        XCTAssertTrue(sut.isDragging)
        XCTAssertTrue(sut.end())
        XCTAssertFalse(sut.end())
        XCTAssertFalse(sut.isDragging)
    }

    func testResetOnlyEndsALiveDrag() {
        var sut = TrackpadDragState()

        XCTAssertFalse(sut.reset())
        XCTAssertTrue(sut.begin())
        XCTAssertTrue(sut.reset())
        XCTAssertFalse(sut.isDragging)
    }

    func testThreeAndFourFingerDefaultsFollowMacOSSemantics() {
        let rows = [
            (
                GestureDefaults.threeFingerSwipeUp,
                GestureDefaults.threeFingerSwipeDown,
                GestureDefaults.threeFingerSwipeLeft,
                GestureDefaults.threeFingerSwipeRight,
                GestureDefaults.threeFingerTap
            ),
            (
                GestureDefaults.fourFingerSwipeUp,
                GestureDefaults.fourFingerSwipeDown,
                GestureDefaults.fourFingerSwipeLeft,
                GestureDefaults.fourFingerSwipeRight,
                GestureDefaults.fourFingerTap
            )
        ]

        for row in rows {
            XCTAssertEqual(row.0, .missionControl)
            XCTAssertEqual(row.1, .appExpose)
            XCTAssertEqual(row.2, .switchSpaceLeft)
            XCTAssertEqual(row.3, .switchSpaceRight)
            XCTAssertEqual(row.4, .none)
        }
    }

    func testPinchKeepsZoomAndRotationStaysOff() {
        XCTAssertEqual(GestureDefaults.pinch, .zoom)
        XCTAssertEqual(GestureDefaults.rotation, .none)
    }

    func testFiveFingerGesturesAreNotRecognized() {
        XCTAssertEqual(TrackpadGestureLimits.maximumFingerCount, 4)
    }
}
