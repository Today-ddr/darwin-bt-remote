import SwiftUI

/// Live count of fingers on the key surface, shared by every touch layer.
///
/// A reference type so the per-key layers, the surface layer and the `@State` in
/// `FullKeyboardView` all count the same fingers. Zero is the floor below which nothing on
/// the surface can legitimately still be held.
final class KeyTouchCount {
    private(set) var value = 0

    /// A finger landed; returns the new total.
    @discardableResult
    func touchDown() -> Int {
        value += 1
        return value
    }

    /// A finger lifted or its touch was cancelled; returns the new total.
    @discardableResult
    func touchUp() -> Int {
        value = max(0, value - 1)
        return value
    }
}

// One transparent touch layer: reports the first finger down and the last finger up, and
// keeps `touches` in step with them.
//
// Release detection deliberately does not go through a SwiftUI gesture. `DragGesture` has
// no cancellation callback, so when the system tears the gesture down — another gesture
// takes over, the view is re-arbitrated during a body re-evaluation — `onEnded` is simply
// never delivered, and a key whose only release path was `onEnded` latched on the host and
// repeated forever. UIKit always ends a touch, with `touchesEnded` or with
// `touchesCancelled` (also reached when the app is interrupted), so a release runs exactly
// once per press. Direct touch handling is what gives that guarantee; a
// `UILongPressGestureRecognizer` or `UITapGestureRecognizer` can be cancelled without a
// terminal event just like a SwiftUI gesture.
#if os(iOS)
    struct KeyCapTouchView: UIViewRepresentable {
        let touches: KeyTouchCount
        var onFirstTouch: () -> Void
        var onLastTouch: () -> Void

        func makeUIView(context: Context) -> TouchView {
            let view = TouchView()
            view.backgroundColor = .clear
            // the labelled key underneath stays the accessible element
            view.isAccessibilityElement = false
            view.accessibilityElementsHidden = true
            view.bind(touches: touches, onFirstTouch: onFirstTouch, onLastTouch: onLastTouch)
            return view
        }

        func updateUIView(_ view: TouchView, context: Context) {
            // rebind so the callbacks stay pointed at the live key state
            view.bind(touches: touches, onFirstTouch: onFirstTouch, onLastTouch: onLastTouch)
        }

        /// Tracks the fingers on this layer and reports the transitions.
        final class TouchView: UIView {
            private var activeTouches: Set<UITouch> = []
            private var count: KeyTouchCount?
            private var onFirstTouch: () -> Void = {}
            private var onLastTouch: () -> Void = {}

            func bind(touches: KeyTouchCount, onFirstTouch: @escaping () -> Void, onLastTouch: @escaping () -> Void) {
                count = touches
                self.onFirstTouch = onFirstTouch
                self.onLastTouch = onLastTouch
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

            // The terminal event a SwiftUI gesture does not have: every touch the system
            // takes away — another gesture winning, an incoming call, the app going to the
            // background — ends up here.
            override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
                super.touchesCancelled(touches, with: event)
                endTouches(touches)
            }

            /// A view torn down mid-touch is never sent `touchesCancelled`, so report the
            /// release as it leaves the window: a key re-created by a body re-evaluation
            /// must not strand the host.
            override func willMove(toWindow newWindow: UIWindow?) {
                super.willMove(toWindow: newWindow)
                guard newWindow == nil, !activeTouches.isEmpty else { return }
                activeTouches.removeAll()
                count?.touchUp()
                onLastTouch()
            }

            private func endTouches(_ touches: Set<UITouch>) {
                activeTouches.subtract(touches)
                guard activeTouches.isEmpty else { return }
                count?.touchUp()
                onLastTouch()
            }
        }
    }
#endif

/// The key rows plus one touch layer of their own, so a finger landing between two keys is
/// still counted and "nothing is down" means the whole surface instead of a single key.
///
/// The layer sits behind the content, not on top of it: a key or the embedded trackpad is
/// nearer to the finger and keeps its own touches, while anything landing in the gaps reaches
/// this layer and the surface count stays honest.
struct KeyCapTouchSurface<Content: View>: View {
    let touches: KeyTouchCount
    var onAllTouchesEnded: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        #if os(iOS)
            // the layer sits behind the keys, so it counts fingers in the gaps without
            // taking touches that belong to a key or to the embedded trackpad
            content()
                .background {
                    KeyCapTouchView(touches: touches, onFirstTouch: {}, onLastTouch: onAllTouchesEnded)
                }
        #else
            content()
        #endif
    }
}
