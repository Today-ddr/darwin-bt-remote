import SwiftUI
import UIKit

/// 1-finger drag: moves
/// 1-finger tap: left-clicks
/// 1-finger double-tap drag: holds the left button for drag (if enabled)
/// 1-finger long-press drag: holds the left button after 0.35 s and 8 pt (if enabled)
/// 2-finger tap: right-clicks
/// 2-finger drag: scrolls (supports direction inversion)
/// 2-finger pinch: zoom (in/out)
/// 2-finger rotation: rotate gesture (off by default)
/// 3-finger swipe: up, down, left, right mapped actions
/// 3-finger tap: mapped action
/// 4-finger swipe: up, down, left, right mapped actions
/// 4-finger tap: mapped action
/// 5-finger gestures are deliberately not recognized.
///
/// Ownership rule: scroll, pinch and rotation all key off two fingers, yet
/// only one of them may act on a given pair of touches. A two-finger pan
/// claims the touches as soon as it begins and keeps them until every touch
/// lifts; a pinch or a rotation is decided before scroll, so it may take the
/// touches only once its separation change or its turn has been sustained for
/// long enough to be unmistakable. Between pinch and rotation, whichever
/// latches first wins, and a claim is never stolen mid-flight. See `Coordinator`.
struct TouchpadView: UIViewRepresentable {
    var moveSensitivity: CGFloat
    var scrollSensitivity: CGFloat
    var invertScroll: Bool
    var doubleTapDragEnabled: Bool
    var longPressDragEnabled: Bool
    /// Attached by the panel so the shared release coordinator can end a drag and
    /// reset two-finger ownership without tearing the surface down.
    var releaseHandle: TouchpadReleaseHandle
    var onMove: (_ dx: Int8, _ dy: Int8, _ isDragging: Bool) -> Void
    var onScroll: (Int8) -> Void
    var onLeftClick: () -> Void
    var onRightClick: () -> Void
    var onDragEnd: () -> Void
    var onGestureAction: (TrackpadGestureAction) -> Void
    var onZoom: (CGFloat) -> Void
    var onRotate: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true
        let c = context.coordinator

        let move = UIPanGestureRecognizer(target: c, action: #selector(Coordinator.handleMove(_:)))
        move.minimumNumberOfTouches = 1
        move.maximumNumberOfTouches = 1
        move.delegate = c

        let scroll = UIPanGestureRecognizer(target: c, action: #selector(Coordinator.handleScroll(_:)))
        scroll.minimumNumberOfTouches = 2
        scroll.maximumNumberOfTouches = 2
        scroll.delegate = c

        let pinch = UIPinchGestureRecognizer(target: c, action: #selector(Coordinator.handlePinch(_:)))
        pinch.delegate = c

        let rotation = UIRotationGestureRecognizer(target: c, action: #selector(Coordinator.handleRotation(_:)))
        rotation.delegate = c

        let longPress = UILongPressGestureRecognizer(target: c, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = LongPressDragPolicy.minimumPressDuration
        longPress.allowableMovement = LongPressDragPolicy.allowableMovement
        longPress.numberOfTouchesRequired = 1
        longPress.delegate = c
        longPress.isEnabled = longPressDragEnabled

        let left = UITapGestureRecognizer(target: c, action: #selector(Coordinator.handleLeft(_:)))
        left.numberOfTouchesRequired = 1
        left.delegate = c
        // A recognized long press suppresses the tap structurally: UIKit fails the
        // tap when the long press wins, so a long-press drag never also left-clicks.
        // When long-press drag is off the recognizer is disabled outright, so it
        // cannot sit in front of the tap and a deliberately slow tap still clicks.
        left.require(toFail: longPress)

        let right = UITapGestureRecognizer(target: c, action: #selector(Coordinator.handleRight))
        right.numberOfTouchesRequired = 2
        right.delegate = c

        let threeTap = UITapGestureRecognizer(target: c, action: #selector(Coordinator.handleThreeFingerTap))
        threeTap.numberOfTouchesRequired = 3
        threeTap.delegate = c

        let fourTap = UITapGestureRecognizer(target: c, action: #selector(Coordinator.handleFourFingerTap))
        fourTap.numberOfTouchesRequired = 4
        fourTap.delegate = c

        let swipeUp = UISwipeGestureRecognizer(target: c, action: #selector(Coordinator.handleSwipeUp))
        swipeUp.numberOfTouchesRequired = 3
        swipeUp.direction = .up
        swipeUp.delegate = c

        let swipeDown = UISwipeGestureRecognizer(target: c, action: #selector(Coordinator.handleSwipeDown))
        swipeDown.numberOfTouchesRequired = 3
        swipeDown.direction = .down
        swipeDown.delegate = c

        let swipeLeft = UISwipeGestureRecognizer(target: c, action: #selector(Coordinator.handleSwipeLeft))
        swipeLeft.numberOfTouchesRequired = 3
        swipeLeft.direction = .left
        swipeLeft.delegate = c

        let swipeRight = UISwipeGestureRecognizer(target: c, action: #selector(Coordinator.handleSwipeRight))
        swipeRight.numberOfTouchesRequired = 3
        swipeRight.direction = .right
        swipeRight.delegate = c

        let fourSwipeUp = UISwipeGestureRecognizer(target: c, action: #selector(Coordinator.handleFourSwipeUp))
        fourSwipeUp.numberOfTouchesRequired = 4
        fourSwipeUp.direction = .up
        fourSwipeUp.delegate = c

        let fourSwipeDown = UISwipeGestureRecognizer(target: c, action: #selector(Coordinator.handleFourSwipeDown))
        fourSwipeDown.numberOfTouchesRequired = 4
        fourSwipeDown.direction = .down
        fourSwipeDown.delegate = c

        let fourSwipeLeft = UISwipeGestureRecognizer(target: c, action: #selector(Coordinator.handleFourSwipeLeft))
        fourSwipeLeft.numberOfTouchesRequired = 4
        fourSwipeLeft.direction = .left
        fourSwipeLeft.delegate = c

        let fourSwipeRight = UISwipeGestureRecognizer(target: c, action: #selector(Coordinator.handleFourSwipeRight))
        fourSwipeRight.numberOfTouchesRequired = 4
        fourSwipeRight.direction = .right
        fourSwipeRight.delegate = c

        c.scrollRecognizer = scroll
        c.pinchRecognizer = pinch
        c.rotationRecognizer = rotation
        c.longPressRecognizer = longPress

        [
            move,
            scroll,
            pinch,
            rotation,
            longPress,
            left,
            right,
            threeTap,
            fourTap,
            swipeUp,
            swipeDown,
            swipeLeft,
            swipeRight,
            fourSwipeUp,
            fourSwipeDown,
            fourSwipeLeft,
            fourSwipeRight
        ]
        .forEach { view.addGestureRecognizer($0) }

        releaseHandle.attach { [weak c] in
            c?.releaseEverything()
        }

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let c = context.coordinator
        c.moveSensitivity = moveSensitivity
        c.scrollSensitivity = scrollSensitivity
        c.invertScroll = invertScroll
        c.doubleTapDragEnabled = doubleTapDragEnabled
        c.longPressDragEnabled = longPressDragEnabled
        c.longPressRecognizer?.isEnabled = longPressDragEnabled
        c.onMove = onMove
        c.onScroll = onScroll
        c.onLeftClick = onLeftClick
        c.onRightClick = onRightClick
        c.onDragEnd = onDragEnd
        c.onGestureAction = onGestureAction
        c.onZoom = onZoom
        c.onRotate = onRotate
    }

    /// The surface is being torn down — the page turned, the layout branch changed, the
    /// panel went away — and a gesture recogniser whose view leaves the hierarchy is
    /// reset rather than ended, so the action method carrying `.ended` / `.cancelled` is
    /// not called at all. A drag that was reporting the left button as held has no
    /// terminal event, so the release has to come from the teardown instead. Releasing
    /// twice is harmless — a drag that already ended leaves nothing to release.
    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.releaseEverything()
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var moveSensitivity: CGFloat = 1
        var scrollSensitivity: CGFloat = 1
        var invertScroll = false
        var doubleTapDragEnabled = true
        var longPressDragEnabled = true
        var onMove: (Int8, Int8, Bool) -> Void = { _, _, _ in }
        var onScroll: (Int8) -> Void = { _ in }
        var onLeftClick: () -> Void = {}
        var onRightClick: () -> Void = {}
        var onDragEnd: () -> Void = {}
        var onGestureAction: (TrackpadGestureAction) -> Void = { _ in }
        var onZoom: (CGFloat) -> Void = { _ in }
        var onRotate: (CGFloat) -> Void = { _ in }

        weak var scrollRecognizer: UIPanGestureRecognizer?
        weak var pinchRecognizer: UIPinchGestureRecognizer?
        weak var rotationRecognizer: UIRotationGestureRecognizer?
        /// Held so `updateUIView` can enable or disable the drag path without
        /// rebuilding the surface. Disabled is the only state in which the
        /// recognizer must not begin: while it is installed and enabled, the tap
        /// waits for it to fail.
        weak var longPressRecognizer: UILongPressGestureRecognizer?

        private var scrollAccumulator: CGFloat = 0
        private let scrollStep: CGFloat = 6

        private var lastTapTime: CFTimeInterval = 0
        private var lastTapLocation: CGPoint = .zero
        private var dragState = TrackpadDragState()
        /// Taps recognized while a drag is live, or in the moment it ends, are not
        /// clicks: the drag already pressed and released the left button.
        private var tapSuppressDeadline: CFTimeInterval = 0

        // MARK: Two-finger ownership

        /// Which two-finger gesture owns the touches right now. Resolved from
        /// state rather than stored as a claim, so it can never go stale.
        private enum TwoFingerOwner {
            case idle
            case scroll
            case pinch
            case rotation
        }

        /// How far the mean finger separation must move, relative to the
        /// separation at the start of the pinch, before the gesture may be
        /// taken as a pinch. Two fingers sliding together across the surface
        /// change their separation by well under 2%, so this is far outside
        /// anything a two-finger scroll produces, while an intentional spread
        /// clears it within a few millimetres of travel.
        private static let pinchLatchRatio: CGFloat = 0.06
        /// …and it must be *sustained*: this many consecutive pinch updates
        /// have to clear the threshold before the pinch may take the touches.
        /// A momentary separation blip cannot latch it.
        private static let pinchLatchEvents = 3
        /// Separation change below which an update counts as noise and resets
        /// the run, so the decisive updates have to be consecutive.
        private static let pinchNoiseRatio: CGFloat = 0.015
        /// Separation the next zoom step is measured from. Measured from the
        /// absolute touch positions rather than `pinch.scale`, which is relative
        /// to the previous read and gets reset as zoom is emitted.
        private var pinchBaselineSeparation: CGFloat?
        /// How far a pinch has to move, net, before it counts as a zoom at all.
        private static let pinchStepRatio: CGFloat = 0.08
        private var pinchLatchStreak = 0
        /// Set once the latching run completes, and held for the rest of the
        /// gesture: the moment a pinch has proved itself it owns the touches.
        private var pinchHasLatched = false

        // MARK: Rotation latch

        /// How far the touches must have turned, in total, before a rotation may
        /// own them. A two-finger scroll barely rotates at all — a few degrees
        /// over its whole travel — while a deliberate turn clears 20° without
        /// effort, so the threshold is far outside scroll noise.
        private static let rotationLatchAngle: CGFloat = 0.35
        /// …and the turn must be *sustained*: this many consecutive updates have
        /// to carry real movement before the total is trusted. A single jump in
        /// the rotation estimate cannot latch it.
        private static let rotationLatchEvents = 3
        /// Per-update movement below which the streak resets, so only consecutive
        /// updates count.
        private static let rotationNoiseAngle: CGFloat = 0.002
        /// Signed total of the turn so far. The sign is what the action reads, so
        /// a hand that wobbles back and forth does not latch on accumulated noise.
        private var rotationAngleAccumulator: CGFloat = 0
        private var rotationLatchStreak = 0
        /// Set once the rotation has proved itself, and held for the rest of the
        /// gesture: the rotation acts once, at the moment it latches, and no later
        /// update can fire it again.
        private var rotationHasLatched = false

        // MARK: Ownership

        /// True while a two-finger pan is running — i.e. while the touches have
        /// been recognised as a scroll.
        private var isScrolling: Bool {
            guard let pan = scrollRecognizer else { return false }
            return pan.state == .began || pan.state == .changed
        }

        /// The ownership rule, in one place:
        ///
        /// 1. A pinch or a rotation outranks a pan once it has latched. A pinch
        ///    only accumulates while no pan is live, as before: a scroll never
        ///    accumulates its way into a pinch, and a pinch that latched in the
        ///    first frames keeps the touches when the pan begins. A rotation keeps
        ///    accumulating through a live pan, because scroll drift can never reach
        ///    its threshold and a deliberate turn must be able to take over.
        /// 2. Between pinch and rotation, whichever latches first owns the touches
        ///    for the rest of the gesture; the other stops accumulating.
        /// 3. Once a gesture owns the touches, nothing else may act on them until
        ///    every touch lifts.
        /// 4. While the owner is still undecided, only scroll may act; a rotation
        ///    that has not latched sends nothing.
        private func twoFingerOwner() -> TwoFingerOwner {
            if pinchHasLatched {
                return .pinch
            }
            if rotationHasLatched {
                return .rotation
            }
            if isScrolling {
                return .scroll
            }
            return .idle
        }

        /// Mean distance of the touches from their own centre — the radius of
        /// the finger spread. Translation-invariant, so two fingers scrolling
        /// leave it unchanged while a pinch moves it directly.
        private func averageSeparation(_ gestureRecognizer: UIGestureRecognizer) -> CGFloat? {
            guard let view = gestureRecognizer.view else { return nil }
            let points = (0 ..< gestureRecognizer.numberOfTouches).map { gestureRecognizer.location(ofTouch: $0, in: view) }
            guard !points.isEmpty else { return nil }
            let centre = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
            let mean = CGPoint(x: centre.x / CGFloat(points.count), y: centre.y / CGFloat(points.count))
            let sum = points.reduce(CGFloat.zero) { $0 + hypot($1.x - mean.x, $1.y - mean.y) }
            return sum / CGFloat(points.count)
        }

        /// Advances the pinch latch, and answers whether the pinch may act.
        /// Nothing accumulates while a pan is live, so no amount of two-finger
        /// scrolling can ever latch a pinch; the latch survives the pan's end now
        /// that the scroll recognizer only resets its own state.
        private func pinchIsSustained(_ pinch: UIPinchGestureRecognizer) -> Bool {
            if pinchHasLatched {
                return true
            }
            guard !rotationHasLatched else { return false }
            guard !isScrolling else { return false }
            // Exactly two fingers: three- and four-finger swipes are mapped to
            // their own actions and must not also latch a zoom.
            guard pinch.numberOfTouches == 2 else { return false }
            guard let separation = averageSeparation(pinch) else { return false }
            if pinchBaselineSeparation == nil {
                pinchBaselineSeparation = separation
            }
            guard let baseline = pinchBaselineSeparation, baseline > 1 else { return false }
            let change = abs(separation / baseline - 1)
            if change > Self.pinchLatchRatio {
                pinchLatchStreak += 1
            } else if change < Self.pinchNoiseRatio {
                pinchLatchStreak = 0
            }
            pinchHasLatched = pinchLatchStreak >= Self.pinchLatchEvents
            return pinchHasLatched
        }

        /// Advances the rotation latch and, when it completes, sends the one
        /// rotation action this gesture is allowed.
        ///
        /// Rotation used to fire whenever it was the owner and a single update
        /// passed 0.25 rad. During the first frames of a scroll a pan has not
        /// begun yet, so ownership was still idle and a tiny drift could send
        /// actions before the scroll even started. Requiring several consecutive
        /// updates and a clearly larger total turn keeps those frames quiet.
        private func advanceRotationLatch(_ rot: UIRotationGestureRecognizer) {
            // `rotation` is cumulative since the last reset. Taking it here and
            // zeroing it turns each update into an increment; a gesture that ends
            // without ever latching therefore leaves nothing behind.
            let delta = rot.rotation
            rot.rotation = 0
            guard rot.numberOfTouches == 2,
                  !rotationHasLatched,
                  !pinchHasLatched
            else { return }
            rotationAngleAccumulator += delta
            if abs(delta) > Self.rotationNoiseAngle {
                rotationLatchStreak += 1
            } else {
                rotationLatchStreak = 0
            }
            guard rotationLatchStreak >= Self.rotationLatchEvents,
                  abs(rotationAngleAccumulator) >= Self.rotationLatchAngle
            else { return }
            rotationHasLatched = true
            onRotate(rotationAngleAccumulator)
        }

        /// Scroll state is only the accumulator `handleScroll` carries between
        /// updates. Only the scroll recognizer's terminal event clears it.
        private func resetScrollState() {
            scrollAccumulator = 0
        }

        /// Pinch state — the baseline it measures against, the streak and the
        /// latch. Only the pinch recognizer's terminal event clears it, so another
        /// gesture ending can no longer drop a live pinch's ownership.
        private func resetPinchState() {
            pinchBaselineSeparation = nil
            pinchLatchStreak = 0
            pinchHasLatched = false
        }

        /// Rotation state. Only the rotation recognizer's terminal event clears it,
        /// so a scroll or a pinch ending cannot clear a live rotation latch.
        private func resetRotationState() {
            rotationAngleAccumulator = 0
            rotationLatchStreak = 0
            rotationHasLatched = false
        }

        /// Everything the surface is holding, given up at once. Called from
        /// `dismantleUIView`, from the panel's registered release, and from the
        /// shared release coordinator: a drag in flight is released once and the
        /// two-finger state is reset so the next pair of fingers starts clean.
        ///
        /// Running when nothing is held is harmless: `endDrag` returns early unless a
        /// drag is live, and the two-finger resets are assignments to defaults.
        func releaseEverything() {
            endDrag()
            resetScrollState()
            resetPinchState()
            resetRotationState()
            lastTapTime = 0
            tapSuppressDeadline = 0
        }

        // MARK: - One finger

        @objc func handleMove(_ pan: UIPanGestureRecognizer) {
            // The `view` guard is per-case rather than up front: `UIGestureRecognizer.view`
            // is weak and already nil once the view is being dismantled, and a terminal
            // event that arrives at that moment must still run the reset. Guarding the
            // whole method on it would drop the one event that clears the drag.
            switch pan.state {
            case .began:
                guard let view = pan.view else { return }
                guard !dragState.isDragging else { return }
                guard doubleTapDragEnabled, pan.numberOfTouches == 1 else { return }
                let now = CACurrentMediaTime()
                let loc = pan.location(in: view)
                let dist = hypot(loc.x - lastTapLocation.x, loc.y - lastTapLocation.y)
                if now - lastTapTime < 0.28, dist < 30 {
                    lastTapTime = 0
                    beginDrag()
                    onMove(0, 0, true)
                }
            case .changed:
                guard let view = pan.view else { return }
                let t = pan.translation(in: view)
                let dx = HIDInput.clamp(t.x * moveSensitivity)
                let dy = HIDInput.clamp(t.y * moveSensitivity)
                if dx != 0 || dy != 0 {
                    onMove(dx, dy, dragState.isDragging)
                    pan.setTranslation(.zero, in: view)
                }
            // `.ended` and `.cancelled` report the release; `.failed` cannot follow a
            // `.began`, but it is listed so that a drag can never be left without a
            // terminal event whatever the state machine does.
            case .ended, .cancelled, .failed:
                endDrag()
            default:
                break
            }
        }

        /// A long press is a drag too, sharing the one `isDragging` flag with the
        /// double-tap path: starting once and ending once is what keeps the host from
        /// seeing two button presses for one gesture.
        ///
        /// The press must be exactly one finger. UIKit fails a long press as soon as
        /// the touch count changes, so a second finger landing before the timer fires
        /// cancels it; the `changed` guard is the belt-and-braces version for a
        /// recognizer that has already begun.
        @objc func handleLongPress(_ press: UILongPressGestureRecognizer) {
            switch press.state {
            case .began:
                guard LongPressDragPolicy.canBegin(
                    isEnabled: longPressDragEnabled,
                    isDragging: dragState.isDragging,
                    touchCount: press.numberOfTouches
                ) else { return }
                lastTapTime = 0
                beginDrag()
                onMove(0, 0, true)
            case .changed:
                if LongPressDragPolicy.cancels(touchCount: press.numberOfTouches) {
                    endDrag()
                }
            case .ended, .cancelled, .failed:
                endDrag()
            default:
                break
            }
        }

        private func beginDrag() {
            guard dragState.begin() else { return }
            tapSuppressDeadline = .greatestFiniteMagnitude
            Haptics.tap(from: .trackpad)
        }

        /// Give up the left button a drag is holding, once. The drag is the only
        /// one-finger state that reaches the host — `onMove` reports it as the left
        /// button being down — so this is the release that has to run, and it runs from
        /// the gesture's terminal event and from the teardown both, which is why it
        /// guards on `isDragging` rather than being called unconditionally.
        private func endDrag() {
            guard dragState.end() else { return }
            // The tap that belongs to the gesture that just ended must not also click.
            // A short window covers a tap recognizer that resolves at the same moment;
            // a later, deliberate tap is past it.
            tapSuppressDeadline = CACurrentMediaTime() + 0.15
            onDragEnd()
        }

        @objc func handleLeft(_ tap: UITapGestureRecognizer) {
            guard let view = tap.view else { return }
            let now = CACurrentMediaTime()
            guard !dragState.isDragging, now >= tapSuppressDeadline else { return }
            lastTapTime = now
            lastTapLocation = tap.location(in: view)
            onLeftClick()
        }

        // MARK: - Two fingers

        @objc func handleScroll(_ pan: UIPanGestureRecognizer) {
            // No `view` guard up front, for the reason in `handleMove`: a terminal event
            // arriving while the view is nil still has to reset the two-finger state, and
            // guarding the method would drop it.
            switch pan.state {
            case .began:
                scrollAccumulator = 0
            case .changed:
                guard let view = pan.view else { return }
                // A pinch or rotation that latched first owns the touches, so the
                // pan that drifts alongside it must not also scroll. The
                // translation is still cleared so nothing is delivered late if the
                // pan outlives the claim.
                let owner = twoFingerOwner()
                guard owner != .pinch, owner != .rotation else {
                    pan.setTranslation(.zero, in: view)
                    return
                }
                scrollAccumulator += pan.translation(in: view).y
                pan.setTranslation(.zero, in: view)
                let step = scrollStep / max(scrollSensitivity, 0.1)
                while abs(scrollAccumulator) >= step {
                    let baseWheel: Int8 = scrollAccumulator > 0 ? -1 : 1
                    let finalWheel: Int8 = invertScroll ? -baseWheel : baseWheel
                    onScroll(finalWheel)
                    scrollAccumulator -= scrollAccumulator > 0 ? step : -step
                    // One detent per emitted wheel step; Haptics throttles the rate.
                    Haptics.scrollTick()
                }
            case .ended, .cancelled, .failed:
                resetScrollState()
            default:
                break
            }
        }

        /// Zoom fires once, when the pinch ends, and never while it is running.
        ///
        /// A pinch squeezes a range, but the only thing a keyboard can express is the
        /// `Cmd+=` / `Cmd+-` shortcut, and every one of those is a full press and
        /// release. Emitting during the gesture turned one pinch into a burst, which
        /// the host reads as "that swipe zoomed ten times". Nothing is sent until the
        /// fingers lift, so the amount sent is one step decided by where it ended up.
        @objc func handlePinch(_ pinch: UIPinchGestureRecognizer) {
            switch pinch.state {
            case .began:
                pinchBaselineSeparation = averageSeparation(pinch)
                pinchLatchStreak = 0
            case .changed:
                // sustain the latch only; the net movement is read when it ends
                _ = pinchIsSustained(pinch)
            case .ended, .cancelled, .failed:
                if let baseline = pinchBaselineSeparation, baseline > 1,
                   let separation = averageSeparation(pinch),
                   pinchHasLatched, twoFingerOwner() == .pinch
                {
                    let netDelta = separation / baseline - 1
                    if abs(netDelta) > Self.pinchStepRatio {
                        onZoom(netDelta)
                    }
                }
                resetPinchState()
            default:
                break
            }
        }

        /// Rotation outranks scroll but loses to a pinch that latched first. Its
        /// default mapping is `none`, so an unconfigured rotation sends nothing.
        @objc func handleRotation(_ rot: UIRotationGestureRecognizer) {
            switch rot.state {
            case .began:
                rot.rotation = 0
            case .changed:
                advanceRotationLatch(rot)
            case .ended, .cancelled, .failed:
                resetRotationState()
            default:
                break
            }
        }

        @objc func handleRight() {
            lastTapTime = 0
            // A two-finger tap that lands while a double-tap drag is in flight ends the
            // drag: the release has to precede the right click, because it reports the
            // button set as it is now.
            endDrag()
            onRightClick()
        }

        // MARK: - Three and four fingers

        @objc func handleThreeFingerTap() {
            Haptics.tap(from: .trackpad)
            let raw = UserDefaults.standard.string(forKey: AppSettings.threeFingerTapKey)
                ?? GestureDefaults.threeFingerTap.rawValue
            if let action = TrackpadGestureAction(rawValue: raw) {
                onGestureAction(action)
            }
        }

        @objc func handleFourFingerTap() {
            Haptics.tap(from: .trackpad)
            let raw = UserDefaults.standard.string(forKey: AppSettings.fourFingerTapKey)
                ?? GestureDefaults.fourFingerTap.rawValue
            if let action = TrackpadGestureAction(rawValue: raw) {
                onGestureAction(action)
            }
        }

        @objc func handleSwipeUp() {
            Haptics.tap(from: .trackpad)
            let raw = UserDefaults.standard.string(forKey: AppSettings.threeFingerSwipeUpKey)
                ?? GestureDefaults.threeFingerSwipeUp.rawValue
            if let action = TrackpadGestureAction(rawValue: raw) {
                onGestureAction(action)
            }
        }

        @objc func handleSwipeDown() {
            Haptics.tap(from: .trackpad)
            let raw = UserDefaults.standard.string(forKey: AppSettings.threeFingerSwipeDownKey)
                ?? GestureDefaults.threeFingerSwipeDown.rawValue
            if let action = TrackpadGestureAction(rawValue: raw) {
                onGestureAction(action)
            }
        }

        @objc func handleSwipeLeft() {
            Haptics.tap(from: .trackpad)
            let raw = UserDefaults.standard.string(forKey: AppSettings.threeFingerSwipeLeftKey)
                ?? GestureDefaults.threeFingerSwipeLeft.rawValue
            if let action = TrackpadGestureAction(rawValue: raw) {
                onGestureAction(action)
            }
        }

        @objc func handleSwipeRight() {
            Haptics.tap(from: .trackpad)
            let raw = UserDefaults.standard.string(forKey: AppSettings.threeFingerSwipeRightKey)
                ?? GestureDefaults.threeFingerSwipeRight.rawValue
            if let action = TrackpadGestureAction(rawValue: raw) {
                onGestureAction(action)
            }
        }

        @objc func handleFourSwipeUp() {
            Haptics.tap(from: .trackpad)
            let raw = UserDefaults.standard.string(forKey: AppSettings.fourFingerSwipeUpKey)
                ?? GestureDefaults.fourFingerSwipeUp.rawValue
            if let action = TrackpadGestureAction(rawValue: raw) {
                onGestureAction(action)
            }
        }

        @objc func handleFourSwipeDown() {
            Haptics.tap(from: .trackpad)
            let raw = UserDefaults.standard.string(forKey: AppSettings.fourFingerSwipeDownKey)
                ?? GestureDefaults.fourFingerSwipeDown.rawValue
            if let action = TrackpadGestureAction(rawValue: raw) {
                onGestureAction(action)
            }
        }

        @objc func handleFourSwipeLeft() {
            Haptics.tap(from: .trackpad)
            let raw = UserDefaults.standard.string(forKey: AppSettings.fourFingerSwipeLeftKey)
                ?? GestureDefaults.fourFingerSwipeLeft.rawValue
            if let action = TrackpadGestureAction(rawValue: raw) {
                onGestureAction(action)
            }
        }

        @objc func handleFourSwipeRight() {
            Haptics.tap(from: .trackpad)
            let raw = UserDefaults.standard.string(forKey: AppSettings.fourFingerSwipeRightKey)
                ?? GestureDefaults.fourFingerSwipeRight.rawValue
            if let action = TrackpadGestureAction(rawValue: raw) {
                onGestureAction(action)
            }
        }

        /// Simultaneous recognition stays allowed, because the two-finger
        /// gestures genuinely need it: a pinch cannot latch a sustained
        /// separation change unless it keeps receiving updates while it is
        /// undecided, and it cannot do that if a pan alongside it has shut it
        /// down. Ownership is therefore decided by the rule in
        /// `twoFingerOwner()`, which every two-finger handler consults — not by
        /// refusing gestures here.
        nonisolated func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }

        /// Five-finger gestures are out of scope; no recognizer may begin with more
        /// than four touches even if the hardware can report them. The long-press
        /// drag recognizer is also refused while the setting is off, so the tap it
        /// is ordered before cannot be held up by a recognizer that must not act.
        nonisolated func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            MainActor.assumeIsolated {
                guard gestureRecognizer.numberOfTouches <= TrackpadGestureLimits.maximumFingerCount else {
                    return false
                }
                if gestureRecognizer === longPressRecognizer, !longPressDragEnabled {
                    return false
                }
                return true
            }
        }
    }
}

/// A non-owning bridge from the SwiftUI panel to the UIKit coordinator, so the
/// shared release coordinator can end a drag without rebuilding or dismantling the
/// touch surface. Only ever touched from the main thread.
final class TouchpadReleaseHandle {
    private var release: (@MainActor () -> Void)?

    @MainActor
    func attach(_ release: @escaping @MainActor () -> Void) {
        self.release = release
    }

    @MainActor
    func releaseNow() {
        release?()
    }
}
