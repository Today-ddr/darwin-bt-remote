#if os(iOS)
    import SwiftUI
    import UIKit

    /// 1-finger drag: moves
    /// 1-finger double-tap drag: drags with left button down (if enabled)
    /// 1-finger tap: left-clicks
    /// 2-finger tap: right-clicks
    /// 2-finger drag: scrolls (supports direction inversion)
    /// Two-finger pinch: zoom (in/out)
    /// 2-finger rotation: rotate gesture
    /// 3-finger swipe: up, down, left, right mapped actions
    /// 3-finger tap: mapped action
    /// 4-finger swipe: up, down, left, right mapped actions
    /// 4-finger tap: mapped action
    ///
    /// Ownership rule: scroll, pinch and rotation all key off two fingers, yet
    /// only one of them may act on a given pair of touches. A two-finger pan
    /// claims the touches as soon as it begins and keeps them until every touch
    /// lifts; a pinch (or rotation) may claim them only while no pan is live and
    /// only once its finger separation has changed enough, for long enough, to be
    /// unmistakably a pinch. First claim wins and is never stolen mid-flight, so
    /// an accidental pinch can no longer interrupt a scroll. See `Coordinator`.
    struct TouchpadView: UIViewRepresentable {
        var moveSensitivity: CGFloat
        var scrollSensitivity: CGFloat
        var invertScroll: Bool
        var doubleTapDragEnabled: Bool
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

            let left = UITapGestureRecognizer(target: c, action: #selector(Coordinator.handleLeft(_:)))
            left.numberOfTouchesRequired = 1
            left.delegate = c

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

            [move, scroll, pinch, rotation, left, right, threeTap, fourTap,
             swipeUp, swipeDown, swipeLeft, swipeRight,
             fourSwipeUp, fourSwipeDown, fourSwipeLeft, fourSwipeRight]
                .forEach { view.addGestureRecognizer($0) }

            return view
        }

        func updateUIView(_ uiView: UIView, context: Context) {
            let c = context.coordinator
            c.moveSensitivity = moveSensitivity
            c.scrollSensitivity = scrollSensitivity
            c.invertScroll = invertScroll
            c.doubleTapDragEnabled = doubleTapDragEnabled
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
        /// not called at all. That is the same defect the keyboard page fixes for touches,
        /// in the gesture recogniser's version of it: a drag that was reporting the left
        /// button as held has no terminal event, so the release has to come from the
        /// teardown instead. Everything the coordinator accumulated is given up here, in one
        /// place, and releasing twice is harmless — a drag that already ended leaves nothing
        /// to release.
        static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
            coordinator.releaseEverything()
        }

        @MainActor
        final class Coordinator: NSObject, UIGestureRecognizerDelegate {
            var moveSensitivity: CGFloat = 1
            var scrollSensitivity: CGFloat = 1
            var invertScroll = false
            var doubleTapDragEnabled = true
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

            private var scrollAccumulator: CGFloat = 0
            private let scrollStep: CGFloat = 6

            private var lastTapTime: TimeInterval = 0
            private var lastTapLocation: CGPoint = .zero
            private var isDragging = false

            // MARK: Two-finger ownership

            /// Which two-finger gesture owns the touches right now. Resolved from
            /// state rather than stored as a claim, so it can never go stale.
            private enum TwoFingerOwner {
                case idle
                case scroll
                case pinch
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
            /// to the previous read and gets reset as zoom is emitted. It is moved up
            /// to the current spread each time a step is emitted — see `handlePinch` —
            /// so every step costs its own further movement instead of every update
            /// re-firing against the spread the pinch began at.
            private var pinchBaselineSeparation: CGFloat?
            /// How much the spread has to move before the next zoom step is emitted.
            /// The baseline is moved up to the spread a step was taken at, so this is
            /// both the arming distance and the emission test, and it is what sets the
            /// zoom rate. The latch that has to clear before any zoom is emitted at all
            /// is a separate rule and is untouched.
            ///
            /// A step is a proportion of the spread rather than a fixed distance, so it
            /// scales with the pinch the way zoom itself does: at the few centimetres two
            /// fingers start a pinch from this is roughly 3 mm of travel, and it stays
            /// proportionate as they spread. The count is therefore log-based — a pinch
            /// that doubles the spread sends ln(2)/ln(1.08) ≈ 9 steps whether it is done
            /// slowly or quickly — which is what keeps the zoom continuous without the
            /// flood a fast pinch used to produce. The old rate had no dependence on
            /// movement at all: once the pinch latched, every update that arrived sent a
            /// step, so the total followed the delivery rate — a 60 Hz update stream put
            /// out one every 17 ms for as long as the fingers stayed down, moving or not.
            /// At 8% a deliberate pinch sends a few steps a second, and one that stops
            /// sends nothing; smaller and the host is carpeted again, much larger and the
            /// zoom arrives in visible jumps.
            private static let zoomStepRatio: CGFloat = 0.08
            private var pinchLatchStreak = 0
            /// Set once the latching run completes, and held for the rest of the
            /// gesture: the moment a pinch has proved itself it owns the touches.
            private var pinchHasLatched = false

            // MARK: Ownership

            /// True while a two-finger pan is running — i.e. while the touches have
            /// been recognised as a scroll.
            private var isScrolling: Bool {
                guard let pan = scrollRecognizer else { return false }
                return pan.state == .began || pan.state == .changed
            }

            /// The ownership rule, in one place:
            ///
            /// 1. Whichever gesture proves itself first owns the touches, and
            ///    keeps them until every touch lifts. A pan proves itself by
            ///    beginning (finger travel); a pinch proves itself by sustaining a
            ///    separation change (`pinchLatchEvents` consecutive updates past
            ///    `pinchLatchRatio`).
            /// 2. Nothing may take the touches from a gesture that already owns
            ///    them, so a scroll can no longer be interrupted by an accidental
            ///    pinch, and a deliberate pinch can no longer be interrupted by
            ///    the slight drift of two fingers.
            /// 3. While the owner is still undecided, nothing acts on the touches.
            ///
            /// The latching run is frozen while a pan is running, so a scroll can
            /// never accumulate its way into a pinch: the freeze is what makes
            /// "first to prove itself wins" safe in both directions.
            private func twoFingerOwner() -> TwoFingerOwner {
                if pinchHasLatched {
                    return .pinch
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
            /// Nothing accumulates while a pan is live, so no amount of
            /// two-finger scrolling can ever latch a pinch.
            private func pinchIsSustained(_ pinch: UIPinchGestureRecognizer) -> Bool {
                if pinchHasLatched {
                    return true
                }
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

            /// Ends the two-finger gesture outright — no lingering lock-out. The
            /// old code held a flag for 150ms after the fingers lifted, which is
            /// what made the surface feel stuck between gestures.
            ///
            /// Every piece of two-finger state is in here, cancellation included:
            /// the accumulator is what `handleScroll` carries between updates, the
            /// baseline is what the pinch measures the spread against, and the streak and
            /// the latch are what decide ownership. A cancelled gesture reaches this too,
            /// through each handler's `.ended, .cancelled` case, so a latch cannot outlive
            /// the touches that set it and block the next pair — a `pinchHasLatched` left
            /// true would make `twoFingerOwner()` return `.pinch` forever, which reads as
            /// a dead surface: the scroll handler's guard drops every update and the
            /// rotation handler's `.idle` test never passes.
            private func endTwoFingerGesture() {
                scrollAccumulator = 0
                pinchBaselineSeparation = nil
                pinchLatchStreak = 0
                pinchHasLatched = false
            }

            /// Everything the surface is holding, given up at once. Called from
            /// `dismantleUIView`, where a recogniser is reset rather than ended and the
            /// handlers that would normally clean up are never called: the view leaves the
            /// hierarchy, UIKit resets its recognisers, and no action message follows. The
            /// release for a drag in flight and the reset of the two-finger state both have
            /// to happen here for that reason.
            ///
            /// Running when nothing is held is harmless: `endDrag` returns early unless a
            /// drag is live, and the two-finger reset is assignments to defaults.
            func releaseEverything() {
                endDrag()
                endTwoFingerGesture()
            }

            @objc func handleMove(_ pan: UIPanGestureRecognizer) {
                // The `view` guard is per-case rather than up front: `UIGestureRecognizer.view`
                // is weak and already nil once the view is being dismantled, and a terminal
                // event that arrives at that moment must still run the reset. Guarding the
                // whole method on it would drop the one event that clears the drag.
                switch pan.state {
                case .began:
                    guard let view = pan.view else { return }
                    if doubleTapDragEnabled {
                        let now = CACurrentMediaTime()
                        let loc = pan.location(in: view)
                        let dist = hypot(loc.x - lastTapLocation.x, loc.y - lastTapLocation.y)
                        if now - lastTapTime < 0.28 && dist < 30 {
                            isDragging = true
                            lastTapTime = 0
                            Haptics.tap(from: .trackpad)
                            onMove(0, 0, true)
                        }
                    }
                case .changed:
                    guard let view = pan.view else { return }
                    let t = pan.translation(in: view)
                    let dx = HIDInput.clamp(t.x * moveSensitivity)
                    let dy = HIDInput.clamp(t.y * moveSensitivity)
                    if dx != 0 || dy != 0 {
                        onMove(dx, dy, isDragging)
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

            /// Give up the left button a double-tap drag is holding, once. The drag is the
            /// only one-finger state that reaches the host — `onMove` reports it as the left
            /// button being down — so this is the release that has to run, and it runs from
            /// the gesture's terminal event and from the teardown both, which is why it
            /// guards on `isDragging` rather than being called unconditionally.
            private func endDrag() {
                guard isDragging else { return }
                isDragging = false
                onDragEnd()
            }

            @objc func handleScroll(_ pan: UIPanGestureRecognizer) {
                // No `view` guard up front, for the reason in `handleMove`: a terminal event
                // arriving while the view is nil still has to reset the two-finger state, and
                // guarding the method would drop it.
                switch pan.state {
                case .began:
                    scrollAccumulator = 0
                case .changed:
                    guard let view = pan.view else { return }
                    // A pinch that latched first owns the touches, so the pan that
                    // drifts alongside it must not also scroll. The translation is
                    // still cleared so nothing is delivered late if the pan
                    // outlives the pinch.
                    guard twoFingerOwner() != .pinch else {
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
                    endTwoFingerGesture()
                default:
                    break
                }
            }

            /// Zoom only, and never before the pinch has sustained its separation
            /// change and taken the touches from the undecided case.
            ///
            /// The emission rate is the step, not the update rate: a step is emitted when
            /// the spread has moved `zoomStepRatio` from `pinchBaselineSeparation`, and
            /// the baseline is then moved up to the spread it was emitted at, so the next
            /// step needs its own further `zoomStepRatio` of movement. Updates that follow
            /// without the fingers having moved read a delta inside the step and emit
            /// nothing, so a pinch that stops stops sending keystrokes, and one held still
            /// sends none at all. Rotation already worked this way — it resets its own
            /// measure as it fires — which is why rotation never machine-gunned the host
            /// while a pinch did.
            @objc func handlePinch(_ pinch: UIPinchGestureRecognizer) {
                switch pinch.state {
                case .began:
                    pinchBaselineSeparation = averageSeparation(pinch)
                    pinchLatchStreak = 0
                case .changed:
                    guard pinchIsSustained(pinch) else { return }
                    guard let baseline = pinchBaselineSeparation, baseline > 1, let separation = averageSeparation(pinch) else { return }
                    let delta = separation / baseline - 1
                    if abs(delta) > Self.zoomStepRatio, twoFingerOwner() == .pinch {
                        onZoom(delta)
                        // Re-arm from the spread just reported. A step is a ratio of the
                        // spread, so it holds its feel as the fingers spread, and the
                        // movement that arms the next one is measured from where this one
                        // was taken rather than from where the pinch began.
                        pinchBaselineSeparation = separation
                    }
                case .ended, .cancelled, .failed:
                    endTwoFingerGesture()
                default:
                    break
                }
            }

            /// Rotation is the last resort for two-finger touches: it acts only
            /// when no pan has begun and no pinch has latched.
            @objc func handleRotation(_ rot: UIRotationGestureRecognizer) {
                switch rot.state {
                case .began:
                    rot.rotation = 0
                case .changed:
                    guard rot.numberOfTouches == 2, twoFingerOwner() == .idle else { return }
                    let delta = rot.rotation
                    if abs(delta) > 0.25 {
                        onRotate(delta)
                        rot.rotation = 0
                    }
                case .ended, .cancelled, .failed:
                    endTwoFingerGesture()
                default:
                    break
                }
            }

            @objc func handleLeft(_ tap: UITapGestureRecognizer) {
                guard let view = tap.view else { return }
                lastTapTime = CACurrentMediaTime()
                lastTapLocation = tap.location(in: view)
                onLeftClick()
            }

            @objc func handleRight() {
                lastTapTime = 0
                // A two-finger tap that lands while a double-tap drag is in flight ends the
                // drag: `isDragging` was cleared without the release going out, so a host
                // that was being dragged by an earlier one-finger gesture kept the left
                // button down until something else cleared it. The release has to precede
                // the right click, because it reports the button set as it is now.
                endDrag()
                onRightClick()
            }

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
            /// `twoFingerOwner()`, which all three handlers consult — not by
            /// refusing gestures here.
            nonisolated func gestureRecognizer(
                _ gestureRecognizer: UIGestureRecognizer,
                shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
            ) -> Bool {
                true
            }
        }
    }
#endif
