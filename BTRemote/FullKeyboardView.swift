import SwiftUI

/// Height the keys settle on once there is room for it. The keyboard page has no
/// embedded trackpad any more, so anything deeper than this is left as margin
/// above and below the rows instead of stretching every cap.
private let maximumKeyHeight: CGFloat = 64
/// Shortest a key gets before the keyboard stops scaling down.
private let minimumKeyHeight: CGFloat = 28
/// How far above a cap its press bubble floats, how much taller than the cap the bubble
/// is, how round its corners are, and how much larger its label is drawn than the cap's.
private let bubbleGap: CGFloat = 4
private let bubbleExtraHeight: CGFloat = 12
private let bubbleCornerRadius: CGFloat = 8
private let bubbleLabelScale: CGFloat = 1.3

struct FullKeyboardView: View {
    let releases: InputReleaseCoordinator

    @Environment(\.hid) private var hid
    @State private var mods: KeyboardModifiers = []
    @State private var isCapsLockOn = false
    /// Keys currently down, reference counted so two fingers on one cap are one
    /// logical press and the key is released only when the last finger leaves.
    @State private var keys = KeyPressTracker()
    /// Fingers on the key surface, shared with every per-key touch layer.
    @StateObject private var surfaceTouches = KeyTouchCount()
    @State private var releaseToken: InputReleaseCoordinator.Token?

    @MainActor
    init(releases: InputReleaseCoordinator) {
        self.releases = releases
    }

    var body: some View {
        // The insets have to be read from a reader ABOVE the `ignoresSafeArea` below, not
        // from the one that sizes the keys: a view that ignores a region reports a zero
        // inset for it, so the inner reader would come back with `leading == 0` in
        // landscape and the padding below would pad nothing. This outer reader still sits
        // in the untouched safe area, so it reports what the system worked out for the
        // device and the orientation we are actually in.
        GeometryReader { outer in
            let insets = outer.safeAreaInsets
            let leadingMargin = FullKeyboardLayoutPolicy.keyHorizontalMargin(
                isLandscape: outer.size.width > outer.size.height,
                safeAreaInset: insets.leading
            )
            let trailingMargin = FullKeyboardLayoutPolicy.keyHorizontalMargin(
                isLandscape: outer.size.width > outer.size.height,
                safeAreaInset: insets.trailing
            )
            GeometryReader { geo in
                keyboard(size: geo.size)
            }
            .padding(.leading, leadingMargin)
            .padding(.trailing, trailingMargin)
            .padding(.vertical, 4)
            // Keep the keys out from under the island and out of the rounded corners, which
            // in landscape sit at the leading and trailing edges. The padding is the system's
            // own safe-area inset rather than a per-model number: the system measures it for
            // the device, the orientation and the window it is actually running in, so an
            // unlisted phone, split view and iPad all follow without a device table to keep
            // current. Portrait reports ~0 sideways and the island is then a top inset, which
            // the vertical insets below already handle, so nothing shrinks there.
            .padding(EdgeInsets(top: 0, leading: insets.leading, bottom: 0, trailing: insets.trailing))
            // The keyboard is still allowed the full width of the device: that reclaims the
            // wide empty margin the safe area would otherwise leave in landscape. The keys
            // themselves stop at the island because of the padding above. Only the horizontal
            // edges are ignored: the vertical insets stay, so the top row still clears the
            // status bar and the bottom row still clears the home indicator.
            .ignoresSafeArea(.container, edges: .horizontal)
        }
        // last line of defence: nothing is touching the surface, so nothing may stay held.
        // This fires now that `KeyTouchCount` publishes its value. Releasing twice is
        // harmless: the tracker is already empty, so the second call changes nothing.
        .onChange(of: surfaceTouches.value) { count in
            if count == 0 {
                releaseEverything()
            }
        }
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

    // MARK: - Keyboard

    /// One six-row layout in both orientations. The rows scale to fill the width
    /// and never scroll: a scroll surface delays touch delivery and its pan
    /// recogniser can cancel a touch that started on a key.
    private func keyboard(size: CGSize) -> some View {
        let gap = FullKeyboardLayoutPolicy.keyGap
        let totalRows = CGFloat(6)
        let availableHeight = size.height - (totalRows - 1) * gap
        let idealKeyHeight = availableHeight / totalRows
        let keyHeight = min(max(idealKeyHeight, minimumKeyHeight), maximumKeyHeight)

        return keyboardLayout(
            rows: [row0, row1, row2, row3, row4, row5],
            size: size,
            gap: gap,
            height: keyHeight,
            isCompact: size.width < size.height
        )
    }

    private func keyboardLayout(
        rows: [[FullKeyCap]],
        size: CGSize,
        gap: CGFloat,
        height: CGFloat,
        isCompact: Bool
    ) -> some View {
        let rowsHeight = CGFloat(rows.count) * height + CGFloat(max(rows.count - 1, 0)) * gap

        return KeyCapTouchSurface(touches: surfaceTouches, onAllTouchesEnded: releaseEverything) {
            VStack(spacing: gap) {
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, keys in
                    keyRow(
                        keys,
                        row: rowIndex,
                        width: size.width,
                        gap: gap,
                        height: height,
                        isCompact: isCompact
                    )
                }
            }
            .frame(width: size.width, height: rowsHeight)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        // The press bubbles are drawn over the whole keyboard instead of inside the row
        // that owns the cap: a row clips to its own bounds, and the top row sits against
        // the top edge of the keyboard, so its bubble has to reach above that row.
        .overlayPreferenceValue(KeyPressBubblePreference.self) { bubbles in
            KeyPressBubbleOverlay(bubbles: bubbles)
        }
    }

    private struct KeyPlacement {
        let column: Int
        let key: FullKeyCap
        let frame: CGRect
    }

    private func keyRow(
        _ keys: [FullKeyCap],
        row rowIndex: Int,
        width: CGFloat,
        gap: CGFloat,
        height: CGFloat,
        isCompact: Bool
    ) -> some View {
        let metrics = KeyboardGridMetrics(width: width, gap: gap)
        var nextStartUnits: CGFloat = 0
        let placements = keys.enumerated().map { column, key -> KeyPlacement in
            let frame = metrics.frame(
                startUnits: nextStartUnits,
                widthUnits: key.weight,
                height: height
            )
            nextStartUnits += key.weight
            return KeyPlacement(column: column, key: key, frame: frame)
        }

        return ZStack(alignment: .topLeading) {
            ForEach(placements, id: \.column) { placement in
                FullKeyCapButton(
                    id: KeyCapID(row: rowIndex, column: placement.column),
                    key: placement.key,
                    isCompact: isCompact,
                    isArmed: isKeyArmed(placement.key),
                    isShiftActive: isShiftActive,
                    surfaceTouches: surfaceTouches,
                    onPress: { handlePress(placement.key) },
                    onRelease: { handleRelease(placement.key) }
                )
                .frame(width: placement.frame.width, height: placement.frame.height)
                .offset(x: placement.frame.minX)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }

    private var isShiftActive: Bool {
        mods.contains(.leftShift) || mods.contains(.rightShift) || isCapsLockOn
    }

    private func isKeyArmed(_ key: FullKeyCap) -> Bool {
        switch key.action {
        case let .modifier(mod):
            mods.contains(mod)
        case .capsLock:
            isCapsLockOn
        case .key:
            false
        }
    }

    private func handlePress(_ key: FullKeyCap) {
        switch key.action {
        case let .key(code):
            keyDown(code)
        case let .modifier(mod):
            toggleMod(mod)
        case .capsLock:
            toggleCapsLock()
        }
    }

    private func handleRelease(_ key: FullKeyCap) {
        if case let .key(code) = key.action {
            keyUp(code)
        }
    }

    private func keyDown(_ code: Keycode) {
        guard keys.press(code) else { return }
        sendHeldKeys()
    }

    /// Releases one finger from `code`; the key itself is released only when the
    /// last finger leaves, which is what the tracker's count decides.
    private func keyUp(_ code: Keycode) {
        guard keys.release(code) else { return }
        sendHeldKeys()
    }

    /// Drops every held key and modifier and clears the host. Safe to call
    /// repeatedly: with nothing held it sends nothing, so a second interruption
    /// cannot produce a second transition.
    private func releaseEverything() {
        let hadKeyboardState = !keys.isEmpty || !mods.isEmpty
        keys.removeAll()
        mods.removeAll()
        guard hadKeyboardState else { return }
        hid.sendKeyboard(.zero)
    }

    private func sendHeldKeys() {
        var effectiveMods = mods
        if isCapsLockOn {
            for key in keys.heldKeys where isLetter(key) {
                effectiveMods.insert(.leftShift)
            }
        }
        hid.sendKeyboard(
            KeyboardReport(
                modifiers: effectiveMods,
                keys: keys.heldKeys.sorted { $0.rawValue < $1.rawValue }
            )
        )
    }

    /// Caps Lock stays a toggle, but the tap is sent with the current held keys
    /// folded in and then followed by the held-key report, so a key that was down
    /// when Caps was tapped is not dropped by the tap's release report.
    private func toggleCapsLock() {
        isCapsLockOn.toggle()
        var reportKeys = keys.heldKeys
        reportKeys.insert(.capsLock)
        hid.sendKeyboard(
            KeyboardReport(
                modifiers: mods,
                keys: reportKeys.sorted { $0.rawValue < $1.rawValue }
            )
        )
        sendHeldKeys()
    }

    private func toggleMod(_ mod: KeyboardModifiers) {
        if mods.contains(mod) {
            mods.subtract(mod)
        } else {
            mods.insert(mod)
        }
        if !keys.isEmpty {
            sendHeldKeys()
        }
    }

    private func isLetter(_ key: Keycode) -> Bool {
        switch key {
        case .a, .b, .c, .d, .e, .f, .g, .h, .i, .j, .k, .l, .m,
             .n, .o, .p, .q, .r, .s, .t, .u, .v, .w, .x, .y, .z:
            true
        default:
            false
        }
    }
}

// MARK: - Key press bubbles

/// Where a cap sits in the layout. Stable for as long as the page is up, so several
/// bubbles on screen at once each keep their own identity.
private struct KeyCapID: Hashable {
    let row: Int
    let column: Int
}

/// A cap that is down right now: what its bubble has to draw, and where the cap is.
///
/// The cap publishes one of these while it is pressed and nothing while it is up, so
/// with nothing held the collection below is empty and there is nothing to draw.
private struct KeyPressBubble: Identifiable {
    let id: KeyCapID
    let label: FullKeyCap.Label
    let isCompact: Bool
    let isArmed: Bool
    let isShiftActive: Bool
    /// The cap's frame, resolved against the overlay's `GeometryReader`.
    let anchor: Anchor<CGRect>
}

/// Gathers the bubble of every cap that is currently down.
private struct KeyPressBubblePreference: PreferenceKey {
    static let defaultValue: [KeyPressBubble] = []

    static func reduce(value: inout [KeyPressBubble], nextValue: () -> [KeyPressBubble]) {
        value.append(contentsOf: nextValue())
    }
}

/// Draws a bubble over every cap that is down, the way the system keyboard lifts the
/// key under a finger.
///
/// The bubbles sit in an overlay covering the whole keyboard rather than in the row
/// that owns the cap: a row would clip them to its own bounds, and the top row is
/// against the top edge, so its bubble has to reach above it. The overlay is not
/// clipped, so a bubble is free to draw in the gap between rows or over the row above.
private struct KeyPressBubbleOverlay: View {
    let bubbles: [KeyPressBubble]

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(bubbles) { bubble in
                    let cap = geo[bubble.anchor]
                    let height = cap.height + bubbleExtraHeight
                    KeyCapBubble(bubble: bubble)
                        .frame(width: cap.width, height: height)
                        .position(x: cap.midX, y: bubbleTop(above: cap, height: height) + height / 2)
                }
            }
        }
        // decoration only: a bubble must never swallow the touch that is holding the
        // key down
        .allowsHitTesting(false)
    }

    /// A bubble floats just above its cap; the top row has no room above it, so its
    /// bubble sits over the cap itself, the way the system keyboard's preview does.
    private func bubbleTop(above cap: CGRect, height: CGFloat) -> CGFloat {
        max(0, cap.minY - (height + bubbleGap))
    }
}

/// One lifted key: the cap's own label, drawn a little larger, on a rounded rect that
/// carries the cap's fill, with a soft shadow so it reads as raised.
private struct KeyCapBubble: View {
    let bubble: KeyPressBubble
    @Environment(\.appTheme) private var appTheme

    var body: some View {
        ZStack {
            // the cap's fill is translucent, so a bubble needs an opaque backing of its
            // own: otherwise the rows behind the lifted key would show straight through
            RoundedRectangle(cornerRadius: bubbleCornerRadius)
                .fill(appTheme.opaquePageBackground)
            RoundedRectangle(cornerRadius: bubbleCornerRadius)
                .fill(bubble.isArmed ? Color.accentColor : appTheme.controlFill)
            KeyCapLabel(
                label: bubble.label,
                isCompact: bubble.isCompact,
                isArmed: bubble.isArmed,
                isShiftActive: bubble.isShiftActive
            )
            .foregroundColor(bubble.isArmed ? .white : .primary)
            .scaleEffect(bubbleLabelScale)
        }
        .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
    }
}

private struct FullKeyCapButton: View {
    let id: KeyCapID
    let key: FullKeyCap
    let isCompact: Bool
    let isArmed: Bool
    let isShiftActive: Bool
    let surfaceTouches: KeyTouchCount
    let onPress: () -> Void
    let onRelease: () -> Void

    @Environment(\.appTheme) private var appTheme
    /// Held only while a finger on this cap is down. `key` stays a value type so a key can
    /// never be stale across the `@State` snapshot, but the flag is dropped the moment the
    /// view carrying it goes away — see `releaseIfStranded`.
    @State private var pressedKey: FullKeyCap?

    var body: some View {
        ZStack {
            KeyCapTouchView(
                touches: surfaceTouches,
                onFirstTouch: press,
                onLastTouch: release
            )
            RoundedRectangle(cornerRadius: 6)
                .fill(isArmed ? Color.accentColor : appTheme.controlFill)
                .allowsHitTesting(false)
            KeyCapLabel(label: key.label, isCompact: isCompact, isArmed: isArmed, isShiftActive: isShiftActive)
                .foregroundColor(isArmed ? .white : .primary)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(pressedKey != nil ? 0.6 : 1)
        // Only the cap that is down publishes its frame, so an idle keyboard sends the
        // overlay an empty list and nothing is drawn.
        .anchorPreference(key: KeyPressBubblePreference.self, value: .bounds) { anchor in
            guard pressedKey != nil else { return [] }
            return [
                KeyPressBubble(
                    id: id,
                    label: key.label,
                    isCompact: isCompact,
                    isArmed: isArmed,
                    isShiftActive: isShiftActive,
                    anchor: anchor
                )
            ]
        }
        .onDisappear { releaseIfStranded() }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(key.accessibility)
    }

    private func press() {
        guard pressedKey == nil else { return }
        pressedKey = key
        Haptics.tap(from: .keyboard)
        onPress()
    }

    private func release() {
        guard pressedKey != nil else { return }
        pressedKey = nil
        onRelease()
    }

    /// Called from `onDisappear`, which is also the last callback a view gets while it is
    /// being torn down: `onRelease` still reports through a live closure, the visual state
    /// going with the view cannot latch anything, and the count below still names the finger
    /// that was on this cap so the surface total does not drift.
    private func releaseIfStranded() {
        guard pressedKey != nil else { return }
        surfaceTouches.touchUp()
        release()
    }
}

/// The label on a key cap. Shared with the press bubble so a lifted key shows the label
/// of the key it came from, and follows the shift state the cap is showing.
private struct KeyCapLabel: View {
    let label: FullKeyCap.Label
    let isCompact: Bool
    let isArmed: Bool
    let isShiftActive: Bool

    var body: some View {
        switch label {
        case let .text(str):
            Text(str)
                .font(.system(size: isCompact ? 11 : 13, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.6)

        case let .letter(char):
            Text(isShiftActive ? char.uppercased() : char.lowercased())
                .font(.system(size: isCompact ? 16 : 17, weight: .semibold))

        case let .dual(top, bottom):
            VStack(spacing: 1) {
                Text(top)
                    .font(.system(size: isCompact ? 9 : 10, weight: isShiftActive ? .bold : .regular))
                    .foregroundColor(isArmed ? .white : (isShiftActive ? .primary : .secondary))
                Text(bottom)
                    .font(.system(size: isCompact ? 11 : 13, weight: isShiftActive ? .regular : .bold))
                    .foregroundColor(isArmed ? .white : (isShiftActive ? .secondary : .primary))
            }

        case let .symbol(sysName, fallback):
            if fallback.isEmpty {
                Image(systemName: sysName)
                    .font(.system(size: isCompact ? 13 : 15, weight: .medium))
            } else {
                HStack(spacing: 3) {
                    Image(systemName: sysName)
                        .font(.system(size: isCompact ? 11 : 13, weight: .medium))
                    Text(fallback)
                        .font(.system(size: isCompact ? 10 : 12, weight: .medium))
                }
            }

        case .capsLock:
            HStack(spacing: 2) {
                Circle()
                    .fill(isArmed ? Color.red : Color.secondary.opacity(0.4))
                    .frame(width: isCompact ? 4 : 5, height: isCompact ? 4 : 5)
                Text("Caps")
                    .font(.system(size: isCompact ? 9 : 11, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }

        case let .modifier(name, symbol, _):
            if isCompact {
                Text(name)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                HStack(spacing: 2) {
                    if !symbol.isEmpty {
                        Text(symbol)
                            .font(.system(size: 11, weight: .medium))
                    }
                    Text(name)
                        .font(.system(size: 11, weight: .medium))
                }
            }
        }
    }
}

#if DEBUG
    #Preview {
        FullKeyboardView(releases: InputReleaseCoordinator())
    }
#endif
