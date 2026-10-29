import SwiftUI

/// Live count of fingers on the key surface, shared by every touch layer.
///
/// A reference type so the per-key layers, the surface layer and the `@StateObject` in
/// `FullKeyboardView` all count the same fingers. Zero is the floor below which nothing on
/// the surface can legitimately still be held.
///
/// Only `isIdle` is published, not the count itself. Every touch callback changes the
/// count, and publishing it re-ran the whole keyboard body on every finger down and up;
/// the view's only question is whether the surface has returned to zero, so `isIdle`
/// changes exactly on the 0↔non-zero boundary and nothing in between. `value` stays
/// readable for tests and for callers that need the total, but changing it alone is not
/// a SwiftUI update.
@MainActor
final class KeyTouchCount: ObservableObject {
    @Published private(set) var isIdle = true
    private(set) var value = 0

    /// A finger landed; returns the new total.
    @discardableResult
    func touchDown() -> Int {
        value += 1
        if value == 1, isIdle {
            isIdle = false
        }
        return value
    }

    /// A finger lifted or its touch was cancelled; returns the new total.
    @discardableResult
    func touchUp() -> Int {
        value = max(0, value - 1)
        if value == 0, !isIdle {
            isIdle = true
        }
        return value
    }
}

/// One transparent touch layer: reports the first finger down and the last finger up, and
/// keeps `touches` in step with them.
///
/// Release detection deliberately does not go through a SwiftUI gesture. `DragGesture` has
/// no cancellation callback, so when the system tears the gesture down — another gesture
/// takes over, the view is re-arbitrated during a body re-evaluation — `onEnded` is simply
/// never delivered, and a key whose only release path was `onEnded` latched on the host and
/// repeated forever. UIKit always ends a touch, with `touchesEnded` or with
/// `touchesCancelled` (also reached when the app is interrupted), so a release runs exactly
/// once per press. Direct touch handling is what gives that guarantee; a
/// `UILongPressGestureRecognizer` or `UITapGestureRecognizer` can be cancelled without a
/// terminal event just like a SwiftUI gesture.
struct KeyCapTouchView: UIViewRepresentable {
    let touches: KeyTouchCount
    var onFirstTouch: () -> Void
    var onLastTouch: () -> Void
    /// Start reporting the fall to zero through `onLastTouch`. False for the per-key
    /// layers — the key tracks its own finger and releases as it always has — and
    /// true only for the surface layer, whose "the last finger left" has to mean the
    /// last finger on the *whole surface*. A finger in the gaps between keys is one
    /// of those fingers, and the surface layer is the only one that sees it; left to
    /// itself, that layer would call the surface empty while a key still had a finger
    /// down, and clear the key. The shared count is what knows better.
    var tracksSurface = false

    func makeUIView(context: Context) -> TouchView {
        let view = TouchView()
        view.backgroundColor = .clear
        // the labelled key underneath stays the accessible element
        view.isAccessibilityElement = false
        view.accessibilityElementsHidden = true
        // A cap shares its surface with every other cap: two fingers landing on two
        // keys at once are two independent presses, not one touch delivered to one view.
        view.isMultipleTouchEnabled = true
        view.bind(
            touches: touches, onFirstTouch: onFirstTouch, onLastTouch: onLastTouch,
            tracksSurface: tracksSurface
        )
        return view
    }

    func updateUIView(_ view: TouchView, context: Context) {
        // rebind so the callbacks stay pointed at the live key state
        view.bind(
            touches: touches, onFirstTouch: onFirstTouch, onLastTouch: onLastTouch,
            tracksSurface: tracksSurface
        )
    }

    /// Tracks the fingers on this layer and reports the transitions.
    final class TouchView: UIView {
        private var activeTouches: Set<UITouch> = []
        private var count: KeyTouchCount?
        private var onFirstTouch: () -> Void = {}
        private var onLastTouch: () -> Void = {}
        private var tracksSurface = false

        func bind(
            touches: KeyTouchCount,
            onFirstTouch: @escaping () -> Void,
            onLastTouch: @escaping () -> Void,
            tracksSurface: Bool
        ) {
            count = touches
            self.onFirstTouch = onFirstTouch
            self.onLastTouch = onLastTouch
            self.tracksSurface = tracksSurface
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesBegan(touches, with: event)
            let wasIdle = activeTouches.isEmpty
            activeTouches.formUnion(touches)
            guard wasIdle else { return }
            count?.touchDown()
            onFirstTouch()
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesEnded(touches, with: event)
            endTouches(touches)
        }

        /// The terminal event a SwiftUI gesture does not have: every touch the system
        /// takes away — another gesture winning, an incoming call, the app going to the
        /// background — ends up here.
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesCancelled(touches, with: event)
            endTouches(touches)
        }

        /// A view torn down mid-touch is never sent `touchesCancelled`, so report the
        /// release as it leaves the window: a key re-created by a body re-evaluation
        /// must not strand the host. The surface layer reports through the count, as
        /// below, so a teardown that takes the gap finger away while a key still has
        /// one down does not clear that key either.
        override func willMove(toWindow newWindow: UIWindow?) {
            super.willMove(toWindow: newWindow)
            guard newWindow == nil, !activeTouches.isEmpty else { return }
            activeTouches.removeAll()
            countDidLeave()
        }

        /// One finger leaving this layer. The shared count is decremented either way —
        /// it counts this layer's fingers, whoever else is on the surface — but only
        /// the surface layer may end the surface, and only when the shared count has
        /// reached zero rather than when this layer's own set empties.
        ///
        /// A finger in the gap between keys is the case this exists for. It lands on
        /// the surface layer behind the keys, so the layer's own set holds it and the
        /// shared count holds it too, on top of the finger a key is pressing. When the
        /// gap finger lifts, the layer's set empties while the count is still 1; with
        /// its own set as the test that layer reported the surface as ended and
        /// cleared the key the other finger was still holding. The count is the only
        /// thing that sees both fingers, so it decides.
        ///
        /// A key releasing its own finger is untouched, because `tracksSurface` is
        /// false there: it releases from the same `touchesEnded` / `touchesCancelled`
        /// it always did — the terminal event UIKit always delivers, and the reason
        /// this component does not use a SwiftUI gesture in the first place.
        private func endTouches(_ touches: Set<UITouch>) {
            activeTouches.subtract(touches)
            guard activeTouches.isEmpty else { return }
            countDidLeave()
        }

        /// The last of this layer's own fingers has gone: hand it back to the shared
        /// count and report the surface ended only if that is what the count now says.
        private func countDidLeave() {
            let remaining = count?.touchUp()
            guard !tracksSurface || remaining == 0 else { return }
            onLastTouch()
        }
    }
}

/// The key rows plus one touch layer of their own, so a finger landing between two keys is
/// still counted and "nothing is down" means the whole surface instead of a single key.
///
/// The layer sits behind the content, not on top of it: a key is nearer to the finger and
/// keeps its own touches, while anything landing in the gaps reaches this layer and the
/// surface count stays honest.
///
/// Being behind the keys is also why `onAllTouchesEnded` runs off the shared count and not
/// off this layer's own touches. This layer sees only the fingers in the gaps; the count
/// sees those and the ones on the keys, so "the surface has ended" is a question only the
/// count can answer. `tracksSurface: true` is what tells the layer to ask it.
struct KeyCapTouchSurface<Content: View>: View {
    let touches: KeyTouchCount
    var onAllTouchesEnded: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        // the layer sits behind the keys, so it counts fingers in the gaps without
        // taking touches that belong to a key
        content()
            .background {
                KeyCapTouchView(
                    touches: touches,
                    onFirstTouch: {},
                    onLastTouch: onAllTouchesEnded,
                    tracksSurface: true
                )
            }
    }
}
