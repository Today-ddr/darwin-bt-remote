import SwiftUI

struct TrackpadPanel: View {
    let hid: HIDInput
    /// Set to false to embed the touch surface alone, without the mouse buttons and scroll column.
    var showsControls = true

    @AppStorage(AppSettings.touchpadSensitivityKey) private var touchpadSensitivity = AppSettings.defaultPointerSensitivity
    @AppStorage(AppSettings.scrollSensitivityKey) private var scrollSensitivity = AppSettings.defaultScrollSensitivity
    @AppStorage(AppSettings.invertScrollKey) private var invertScroll = false
    @AppStorage(AppSettings.doubleTapDragKey) private var doubleTapDrag = true
    @AppStorage(AppSettings.pinchGestureActionKey) private var pinchActionRaw = TrackpadGestureAction.zoom.rawValue
    @AppStorage(AppSettings.rotationGestureActionKey) private var rotateActionRaw = TrackpadGestureAction.rotateRight.rawValue
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
            } else {
                surface
            }
        }
    }

    private var surface: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(groupFill)
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

    private func handlePinchZoom(delta: CGFloat) {
        let action = TrackpadGestureAction(rawValue: pinchActionRaw) ?? .zoom
        if action == .zoom {
            let key: Keycode = delta > 0 ? .equal : .minus
            hid.tap(key, modifiers: .leftGUI)
        } else {
            action.execute(hid: hid)
        }
    }

    private func handleRotation(delta: CGFloat) {
        let action = TrackpadGestureAction(rawValue: rotateActionRaw)
        if action == .rotateRight || action == .rotateLeft || action == nil {
            if delta > 0 {
                TrackpadGestureAction.rotateRight.execute(hid: hid)
            } else {
                TrackpadGestureAction.rotateLeft.execute(hid: hid)
            }
        } else {
            action?.execute(hid: hid)
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
            background: { RoundedRectangle(cornerRadius: 12).fill(groupFill) },
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
            background: { RoundedRectangle(cornerRadius: 12).fill(groupFill) },
            label: { Image(systemName: icon).font(.body) }
        )
        .accessibilityLabel(label)
    }
}
