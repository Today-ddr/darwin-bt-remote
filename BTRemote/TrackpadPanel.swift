import SwiftUI

struct TrackpadPanel: View {
    let hid: HIDInput
    let releases: InputReleaseCoordinator

    @Environment(\.appTheme) private var appTheme
    @AppStorage(AppSettings.touchpadSensitivityKey) private var touchpadSensitivity = AppSettings.defaultPointerSensitivity
    @AppStorage(AppSettings.scrollSensitivityKey) private var scrollSensitivity = AppSettings.defaultScrollSensitivity
    @AppStorage(AppSettings.invertScrollKey) private var invertScroll = false
    @AppStorage(AppSettings.doubleTapDragKey) private var doubleTapDrag = true
    @AppStorage(AppSettings.longPressDragKey) private var longPressDrag = true
    @AppStorage(AppSettings.pinchGestureActionKey) private var pinchActionRaw = GestureDefaults.pinch.rawValue
    @AppStorage(AppSettings.rotationGestureActionKey) private var rotateActionRaw = GestureDefaults.rotation.rawValue
    @State private var activeButtons: MouseButtons = []
    @State private var releaseToken: InputReleaseCoordinator.Token?
    @State private var releaseHandle = TouchpadReleaseHandle()

    @MainActor
    init(hid: HIDInput, releases: InputReleaseCoordinator) {
        self.hid = hid
        self.releases = releases
    }

    var body: some View {
        HStack(spacing: cellGap) {
            surface
            scrollColumn.frame(width: 46)
        }
        .frame(maxHeight: .infinity)
        .onAppear {
            releaseToken = releases.register { releaseEverything() }
        }
        .onDisappear {
            if let releaseToken {
                releases.unregister(releaseToken)
                self.releaseToken = nil
            }
            releaseEverything()
        }
    }

    private var surface: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(appTheme.controlFill)
            TouchpadView(
                moveSensitivity: touchpadSensitivity,
                scrollSensitivity: scrollSensitivity,
                invertScroll: invertScroll,
                doubleTapDragEnabled: doubleTapDrag,
                longPressDragEnabled: longPressDrag,
                releaseHandle: releaseHandle,
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Idempotent: the drag is released once, the three pointer buttons are let go,
    /// and a zero report goes out only when something was actually held. A second
    /// call while nothing is held produces no second button transition.
    private func releaseEverything() {
        let hadButtons = !activeButtons.isEmpty
        releaseHandle.releaseNow()
        activeButtons = []
        if hadButtons {
            hid.sendMouse(.zero)
        }
    }

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
    /// A rotation event carries an angle and HID keyboard and mouse reports
    /// cannot express one, so there is no faithful binding to fall back to. The
    /// rotate actions stay in the picker for anyone who wants them, but they
    /// are chosen, never assumed.
    private func handleRotation(delta: CGFloat) {
        let action = TrackpadGestureAction(rawValue: rotateActionRaw) ?? GestureDefaults.rotation
        switch action {
        case .none:
            break
        case .rotateRight, .rotateLeft:
            if delta > 0 {
                TrackpadGestureAction.rotateRight.execute(hid: hid)
            } else {
                TrackpadGestureAction.rotateLeft.execute(hid: hid)
            }
        default:
            action.execute(hid: hid)
        }
    }

    private var scrollColumn: some View {
        VStack(spacing: cellGap) {
            scrollButton("arrow.up", L10n.Mouse.wheelUp, direction: 1)
            middleButton
            scrollButton("arrow.down", L10n.Mouse.wheelDown, direction: -1)
        }
    }

    /// Middle click, held down for as long as the button is pressed.
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

    /// One tap is one small relative wheel step. The sign follows the natural /
    /// inverted preference, the built-in press haptic is silenced so the scroll
    /// tick is the only feedback, and `HIDInput.scroll` sends the wheel report
    /// alone — no zero immediately behind it that the host could coalesce away.
    private func scrollButton(_ icon: String, _ label: LocalizedStringKey, direction: Int8) -> some View {
        HoldButton(
            onPress: {
                hid.scroll(
                    ScrollStep.wheel(
                        direction: direction,
                        scrollSensitivity: scrollSensitivity,
                        invertScroll: invertScroll
                    )
                )
                Haptics.scrollTick()
            },
            onRelease: {},
            hapticSource: nil,
            background: { RoundedRectangle(cornerRadius: 12).fill(appTheme.controlFill) },
            label: { Image(systemName: icon).font(.body) }
        )
        .accessibilityLabel(label)
    }
}

#if DEBUG
    #Preview {
        TrackpadPanel(hid: .unavailable, releases: InputReleaseCoordinator())
            .padding()
    }
#endif
