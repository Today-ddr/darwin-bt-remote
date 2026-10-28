import CoreGraphics
import Foundation

/// One drag at a time, shared by the double-tap path and the long-press path.
///
/// `begin` and `end` answer whether they changed anything, so a gesture can only
/// press the left button once and release it once no matter which path started it.
struct TrackpadDragState: Equatable {
    private(set) var isDragging = false

    /// Returns true only for the transition that actually starts a drag.
    @discardableResult
    mutating func begin() -> Bool {
        guard !isDragging else { return false }
        isDragging = true
        return true
    }

    /// Returns true only for the transition that actually ends a drag.
    @discardableResult
    mutating func end() -> Bool {
        guard isDragging else { return false }
        isDragging = false
        return true
    }

    @discardableResult
    mutating func reset() -> Bool {
        end()
    }
}

/// Five-finger gestures are out of scope: the surface recognizes one to four
/// fingers and nothing beyond them.
enum TrackpadGestureLimits {
    static let maximumFingerCount = 4
}

/// The long-press drag gate: 0.35 seconds, 8 points of movement, exactly one
/// touch. A second touch before the timer fires cancels the press; UIKit fails the
/// recognizer as soon as the touch count changes, and the coordinator applies the
/// same rule to an already-running press.
enum LongPressDragPolicy {
    static let minimumPressDuration: TimeInterval = 0.35
    static let allowableMovement: CGFloat = 8

    static func canBegin(
        isEnabled: Bool,
        isDragging: Bool,
        touchCount: Int
    ) -> Bool {
        isEnabled && !isDragging && touchCount == 1
    }

    static func cancels(touchCount: Int) -> Bool {
        touchCount != 1
    }
}
