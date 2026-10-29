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

    /// Finger count feeding the surface total. The layer reports only its own
    /// transitions; the count is the shared type `KeyCapTouchView` is given.
    @State private var touches = KeyTouchCount()

    func body(content: Content) -> some View {
        content
            .overlay {
                KeyCapTouchView(
                    touches: touches,
                    onFirstTouch: press,
                    onLastTouch: release
                )
            }
            .contentShape(Rectangle())
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
