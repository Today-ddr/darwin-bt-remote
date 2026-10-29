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
    /// The left button a drag is holding. Kept as state so every report — a move, a
    /// click pulse, the middle button — can merge the same button set instead of
    /// replacing it with the one button it happens to care about.
    @State private var isDragging = false
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
            guard releaseToken == nil else { return }
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
                onMove: { dx, dy, dragging in
                    // Only touch state when the drag flag actually changes: writing the
                    // same value on every move still invalidates this panel's body, which
                    // is every frame of a drag.
                    if isDragging != dragging {
                        isDragging = dragging
                    }
                    hid.sendMouse(MouseReport(buttons: buttons(dragging: dragging), dX: dx, dY: dy))
                },
                onScroll: { hid.scroll($0) },
                onLeftClick: { Haptics.tap(from: .trackpad); pulse(.left) },
                onRightClick: { Haptics.tap(from: .trackpad); pulse(.right) },
                onDragEnd: {
                    isDragging = false
                    hid.sendMouse(MouseReport(buttons: buttons(dragging: false)))
                },
                onGestureAction: { action in
                    // A middle click is a mouse button, so it has to go through the
                    // same merged button set rather than `HIDInput.click`, which would
                    // report middle alone and release everything else that is held.
                    if action == .middleClick {
                        pulse(.middle)
                    } else {
                        action.execute(hid: hid)
                    }
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
        let hadButtons = !activeButtons.isEmpty || isDragging
        releaseHandle.releaseNow()
        activeButtons = []
        isDragging = false
        if hadButtons {
            hid.sendMouse(.zero)
        }
    }

    /// The one button set every report is built from: the buttons the panel is
    /// holding plus the left button a drag is holding. Sending a report from anything
    /// narrower would drop the other buttons on the host.
    private var currentButtons: MouseButtons {
        buttons(dragging: isDragging)
    }

    private func buttons(dragging: Bool) -> MouseButtons {
        var buttons = activeButtons
        if dragging {
            buttons.insert(.left)
        }
        return buttons
    }

    /// One click without losing the other buttons: press the clicked button on top of
    /// the current set, then send exactly that set again. A middle button that is held
    /// through a left click, or a drag's left button held through a middle click, stays
    /// down across the whole pair.
    private func pulse(_ button: MouseButtons) {
        let held = currentButtons
        hid.sendMouse(MouseReport(buttons: held.union(button)))
        hid.sendMouse(MouseReport(buttons: held))
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

    /// Middle click, held down for as long as the button is pressed. The reports
    /// include the drag's left button, so pressing middle during a drag does not
    /// quietly let go of the drag.
    private var middleButton: some View {
        HoldButton(
            onPress: {
                activeButtons.insert(.middle)
                hid.sendMouse(MouseReport(buttons: currentButtons))
            },
            onRelease: {
                activeButtons.remove(.middle)
                hid.sendMouse(MouseReport(buttons: currentButtons))
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
