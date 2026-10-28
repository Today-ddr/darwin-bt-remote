import SwiftUI

let cellGap: CGFloat = 6

/// Shared metrics for the pill controls that sit above the content: the page switcher
/// on the input tab and the bottom page switch. They are meant to read as one row of
/// like controls, so their sizes live here rather than being spelled out at each call
/// site.
enum ChipMetrics {
    static let iconSize: CGFloat = 12
    /// A chip with a label sizes itself with this padding.
    static let labelPadding: CGFloat = 6
    static let cornerRadius: CGFloat = 8
    static let rowSpacing: CGFloat = 6
    /// Side margin for a page's content, so the switcher and the panel below it line up
    /// across pages.
    static let pageHorizontalPadding: CGFloat = 8
}

/// fires once on press and once on release; shared by hold-to-send controls
///
/// Release detection is the UIKit touch layer, not a SwiftUI gesture. `DragGesture`
/// has no cancellation callback, so a press whose gesture is torn down — the system takes
/// it away for another gesture, the view is re-arbitrated during a body re-evaluation, the
/// app is interrupted — never runs `onEnded`, and the host is left holding the key or the
/// consumer code until something else clears it. UIKit ends every touch it starts, with
/// `touchesEnded` or with `touchesCancelled`, so a release runs exactly once per press; see
/// `KeyCapTouchView`, which is where that guarantee lives.
///
/// `onDisappear` is attached as a last line of defence, so a control whose view goes
/// away while it is down — a page switch, a re-laid-out geometry branch — reports the
/// release even where no terminal event arrives.
struct PressGesture: ViewModifier {
    let onPress: () -> Void
    let onRelease: () -> Void
    @Binding var pressed: Bool
    /// `nil` silences the built-in press feedback for controls that report a
    /// dedicated haptic of their own, such as the scroll buttons.
    var hapticSource: Haptics.Source? = .keyboard
    /// Region of the content that may take the press, in the content's own coordinates.
    /// `nil` (the default) is the whole frame, which is what every rectangle control wants.
    var region: (@Sendable (CGRect) -> Path)?

    /// Finger count feeding the surface total. The layer reports only its own
    /// transitions; the count is the shared type `KeyCapTouchView` is given.
    @State private var touches = KeyTouchCount()

    func body(content: Content) -> some View {
        // `contentShape` is applied unconditionally, with the frame standing in when
        // there is no region: an `if let` here would put the two cases behind a
        // `_ConditionalContent`, and a conditional that changes branch identity as a
        // property changes is a view SwiftUI may rebuild rather than update.
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
    }

    private func press() {
        guard !pressed else { return }
        pressed = true
        if let hapticSource {
            Haptics.tap(from: hapticSource)
        }
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
    var hapticSource: Haptics.Source? = .keyboard
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
