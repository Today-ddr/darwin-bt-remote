import SwiftUI

let groupFill = Color.secondary.opacity(0.16)
let cellGap: CGFloat = 6

/// fires once on press and once on release; shared by hold-to-send controls
///
/// Release detection is the UIKit touch layer on iOS, not a SwiftUI gesture. `DragGesture`
/// has no cancellation callback, so a press whose gesture is torn down — the system takes it
/// away for another gesture, the view is re-arbitrated during a body re-evaluation, the app
/// is interrupted — never runs `onEnded`, and the host is left holding the key or the
/// consumer code until something else clears it. UIKit ends every touch it starts, with
/// `touchesEnded` or with `touchesCancelled`, so a release runs exactly once per press; see
/// `KeyCapTouchView`, which is where that guarantee lives and why the keyboard page uses it
/// too.
///
/// macOS keeps the gesture, and so keeps what it had before: those pages are driven by the
/// mouse, where there is no touch layer to borrow, and the keyboard page takes the same
/// route there. `onDisappear` is attached on both platforms as a last line of defence, so a
/// control whose view goes away while it is down — a page switch, a `TabView` off-screen, a
/// re-laid-out geometry branch — reports the release even where no terminal event arrives.
struct PressGesture: ViewModifier {
    let onPress: () -> Void
    let onRelease: () -> Void
    @Binding var pressed: Bool
    var hapticSource: Haptics.Source = .keyboard
    /// Region of the content that may take the press, in the content's own coordinates.
    /// `nil` (the default) is the whole frame, which is what every rectangle control wants.
    /// A control that is not a rectangle — the D-pad's wedges and its centre button — passes
    /// the shape it draws instead, so the touch layer and SwiftUI's own hit testing agree on
    /// where it is. Without it, four wedges sharing one square would each claim the whole
    /// square and only the last one drawn would ever be pressed.
    var region: (@Sendable (CGRect) -> Path)?

    /// Fingers on this control's layer. Only its own transitions are reported — the layer is
    /// not the keyboard's surface layer — but the count is the shared type `KeyCapTouchView`
    /// binds to, held in `@State` so it survives a rebind of the view.
    @State private var touches = KeyTouchCount()

    func body(content: Content) -> some View {
        #if os(iOS)
            // `contentShape` is applied unconditionally, with the frame standing in when
            // there is no region: an `if let` here would put the two cases behind a
            // `_ConditionalContent`, and a conditional that changes branch identity as a
            // property changes is a view SwiftUI may rebuild rather than update. The frame
            // rectangle is what the default hit testing already accepts, so the `nil` case
            // behaves exactly as it did before this existed.
            content
                .overlay {
                    KeyCapTouchView(
                        touches: touches,
                        onFirstTouch: press,
                        onLastTouch: release,
                        region: region
                    )
                }
                .contentShape(RegionShape(region: region))
                .onDisappear(perform: release)
        #else
            content
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in press() }
                        .onEnded { _ in release() }
                )
                .onDisappear(perform: release)
        #endif
    }

    private func press() {
        guard !pressed else { return }
        pressed = true
        Haptics.tap(from: hapticSource)
        onPress()
    }

    private func release() {
        guard pressed else { return }
        pressed = false
        onRelease()
    }
}

/// A `Shape` drawn by a closure, so `PressGesture` can hand SwiftUI the region a shaped
/// control occupies without having to know the shape's type. A `nil` region is the whole
/// rect — the frame every rectangular control is hit by anyway.
private struct RegionShape: Shape {
    let region: (@Sendable (CGRect) -> Path)?

    func path(in rect: CGRect) -> Path {
        region?(rect) ?? Path(rect)
    }
}

struct HoldButton<Background: View, Label: View>: View {
    let onPress: () -> Void
    let onRelease: () -> Void
    var hapticSource: Haptics.Source = .keyboard
    @ViewBuilder var background: () -> Background
    @ViewBuilder var label: () -> Label
    @State private var pressed = false

    var body: some View {
        ZStack {
            background()
            label().foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(pressed ? 0.5 : 1)
        .contentShape(Rectangle())
        .modifier(
            PressGesture(
                onPress: onPress,
                onRelease: onRelease,
                pressed: $pressed,
                hapticSource: hapticSource
            )
        )
    }
}
