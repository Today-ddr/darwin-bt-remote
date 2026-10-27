import SwiftUI

struct TrackpadPanel: View {
    let hid: HIDInput
    /// Set to false to embed the touch surface alone, without the mouse buttons and scroll column.
    var showsControls = true

    @Environment(\.appTheme) private var appTheme
    @AppStorage(AppSettings.touchpadSensitivityKey) private var touchpadSensitivity = AppSettings.defaultPointerSensitivity
    @AppStorage(AppSettings.scrollSensitivityKey) private var scrollSensitivity = AppSettings.defaultScrollSensitivity
    @AppStorage(AppSettings.invertScrollKey) private var invertScroll = false
    @AppStorage(AppSettings.doubleTapDragKey) private var doubleTapDrag = true
    @AppStorage(AppSettings.pinchGestureActionKey) private var pinchActionRaw = GestureDefaults.pinch.rawValue
    @AppStorage(AppSettings.rotationGestureActionKey) private var rotateActionRaw = GestureDefaults.rotation.rawValue
    @State private var activeButtons: MouseButtons = []
    #if os(macOS)
        @State private var dragOffset: CGSize = .zero
    #endif

    var body: some View {
        VStack(spacing: cellGap) {
            if showsControls {
                HStack(spacing: cellGap) {
                    surface
                    scrollColumn.frame(width: 46)
                }
                .frame(maxHeight: .infinity)
                #if os(macOS)
                    // The touch surface is a bare `DragGesture` on macOS: it carries
                    // pointer movement and nothing else, and `TouchpadView` — which is
                    // where left and right click come from on iOS — is inside
                    // `#if os(iOS)`. Without this row the buttons that used to sit here
                    // would leave macOS with no way to click at all, so the pointer pair
                    // is restored for macOS only. The middle button it replaced stays in
                    // the scroll column above, so only the two that had no other home
                    // are repeated here.
                    pointerButtonsRow
                #endif
            } else {
                surface
            }
        }
    }

    private var surface: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(appTheme.controlFill)
            #if os(iOS)
                TouchpadView(
                    moveSensitivity: touchpadSensitivity,
                    scrollSensitivity: scrollSensitivity,
                    invertScroll: invertScroll,
                    doubleTapDragEnabled: doubleTapDrag,
                    onMove: { dx, dy, isDragging in
                        var buttons = activeButtons
                        if isDragging {
                            buttons.insert(.left)
                        }
                        hid.sendMouse(MouseReport(buttons: buttons, dX: dx, dY: dy))
                    },
                    onScroll: { hid.scroll($0) },
                    onLeftClick: { Haptics.tap(from: .trackpad); hid.click(.left) },
                    onRightClick: { Haptics.tap(from: .trackpad); hid.click(.right) },
                    onDragEnd: {
                        hid.sendMouse(MouseReport(buttons: activeButtons))
                    },
                    onGestureAction: { action in
                        action.execute(hid: hid)
                    },
                    onZoom: { delta in
                        handlePinchZoom(delta: delta)
                    },
                    onRotate: { delta in
                        handleRotation(delta: delta)
                    }
                )
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(macOS)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let dx = HIDInput.clamp((value.translation.width - dragOffset.width) * touchpadSensitivity)
                        let dy = HIDInput.clamp((value.translation.height - dragOffset.height) * touchpadSensitivity)
                        dragOffset = value.translation
                        hid.sendMouse(MouseReport(buttons: activeButtons, dX: dx, dY: dy))
                    }
                    .onEnded { _ in
                        dragOffset = .zero
                        hid.sendMouse(MouseReport(buttons: activeButtons))
                    }
            )
        #endif
    }

    // Left and right click, restored for macOS.
    //
    // macOS gets its clicks from here and nowhere else: the trackpad surface itself
    // only reports pointer movement, and the iOS touch gestures — the one-finger tap
    // for a left click and the two-finger tap for a right click — are not built on
    // macOS. A row of two buttons under the touch surface is the smallest thing that
    // puts both back, and it sits where the left / middle / right row was before the
    // middle button moved into the scroll column, so the panel keeps its old shape.
    // They are `HoldButton`s, as that row was, so they hold the button down and drag
    // like the ones they replaced rather than only clicking on release.
    #if os(macOS)
        private var pointerButtonsRow: some View {
            HStack(spacing: cellGap) {
                mouseButton(.left, "cursorarrow.click", L10n.Mouse.leftButton)
                mouseButton(.right, "cursorarrow.click.2", L10n.Mouse.rightButton)
            }
            .frame(height: 44)
        }

        private func mouseButton(_ button: MouseButtons, _ icon: String, _ label: LocalizedStringKey) -> some View {
            HoldButton(
                onPress: {
                    activeButtons.insert(button)
                    hid.sendMouse(MouseReport(buttons: activeButtons))
                },
                onRelease: {
                    activeButtons.remove(button)
                    hid.sendMouse(MouseReport(buttons: activeButtons))
                },
                hapticSource: .trackpad,
                background: { RoundedRectangle(cornerRadius: 12).fill(appTheme.controlFill) },
                label: { Image(systemName: icon).font(.body) }
            )
            .accessibilityLabel(label)
        }
    #endif

    /// Pinch falls back to zoom, which is the closest a keyboard can come to a
    /// MacBook pinch: a real pinch reports a continuous separation, and the
    /// `Cmd+=` / `Cmd+-` pair is the one pairing macOS itself uses for the same
    /// job, so the fallback stays zoom rather than following rotation to `none`.
    private func handlePinchZoom(delta: CGFloat) {
        let action = TrackpadGestureAction(rawValue: pinchActionRaw) ?? GestureDefaults.pinch
        if action == .zoom {
            let key: Keycode = delta > 0 ? .equal : .minus
            hid.tap(key, modifiers: .leftGUI)
        } else {
            action.execute(hid: hid)
        }
    }

    /// Rotation is unset by default, and unset means do nothing.
    ///
    /// It used to mean `rotateRight`, which sends `Cmd+R` — the frontmost app's
    /// refresh/restart shortcut — so a two-finger turn the user did not intend
    /// as a rotation could reload or restart whatever app was in front. A
    /// rotation event carries an angle and HID keyboard and mouse reports
    /// cannot express one, so there is no faithful binding to fall back to; the
    /// rotate actions stay in the picker for anyone who wants them, but they
    /// are chosen, never assumed.
    private func handleRotation(delta: CGFloat) {
        let action = TrackpadGestureAction(rawValue: rotateActionRaw) ?? GestureDefaults.rotation
        switch action {
        case .none:
            break
        case .rotateRight, .rotateLeft:
            // Both directions share this gesture, so the one that was picked is
            // the one that runs. The default (`none`) is handled above and
            // never reaches here.
            if delta > 0 {
                TrackpadGestureAction.rotateRight.execute(hid: hid)
            } else {
                TrackpadGestureAction.rotateLeft.execute(hid: hid)
            }
        default:
            action.execute(hid: hid)
        }
    }

    private var scrollAmount: Int8 {
        max(1, HIDInput.clamp(CGFloat(3 * scrollSensitivity)))
    }

    private var scrollColumn: some View {
        VStack(spacing: cellGap) {
            scrollButton("arrow.up", L10n.Mouse.wheelUp, scrollAmount)
            middleButton
            scrollButton("arrow.down", L10n.Mouse.wheelDown, -scrollAmount)
        }
    }

    /// Middle click, held down for as long as the button is pressed just like
    /// the pointer buttons it used to sit beside.
    private var middleButton: some View {
        HoldButton(
            onPress: {
                activeButtons.insert(.middle)
                hid.sendMouse(MouseReport(buttons: activeButtons))
            },
            onRelease: {
                activeButtons.remove(.middle)
                hid.sendMouse(MouseReport(buttons: activeButtons))
            },
            hapticSource: .trackpad,
            background: { RoundedRectangle(cornerRadius: 12).fill(appTheme.controlFill) },
            label: { Image(systemName: "computermouse").font(.body) }
        )
        .accessibilityLabel(L10n.Mouse.middleButton)
    }

    private func scrollButton(_ icon: String, _ label: LocalizedStringKey, _ wheel: Int8) -> some View {
        HoldButton(
            onPress: {
                hid.scroll(wheel)
                Haptics.scrollTick()
            },
            onRelease: {},
            hapticSource: .trackpad,
            background: { RoundedRectangle(cornerRadius: 12).fill(appTheme.controlFill) },
            label: { Image(systemName: icon).font(.body) }
        )
        .accessibilityLabel(label)
    }
}
