import SwiftUI

/// Leftover height below the key rows under which a trackpad would be too cramped to use.
private let trackpadMinimumHeight: CGFloat = 80
/// Keeps the embedded touch surface clear of the home indicator and the swipe-up gesture.
private let trackpadBottomInset: CGFloat = 8
/// Height the keys settle on once there is room for it. Anything deeper than this below
/// the rows is left to the trackpad, so the keys stop growing here.
private let maximumKeyHeight: CGFloat = 52
/// Shortest a key gets before the keyboard stops scaling down.
private let minimumKeyHeight: CGFloat = 28
/// Space kept either side of the keys. The keyboard is allowed into the horizontal safe
/// area (see `body`), so this margin is what stands between the outermost keys and the
/// edge of the screen.
private let keyHorizontalMargin: CGFloat = 8
/// How far above a cap its press bubble floats, how much taller than the cap the bubble
/// is, how round its corners are, and how much larger its label is drawn than the cap's.
private let bubbleGap: CGFloat = 4
private let bubbleExtraHeight: CGFloat = 12
private let bubbleCornerRadius: CGFloat = 8
private let bubbleLabelScale: CGFloat = 1.3

struct FullKeyboardView: View {
    @Environment(\.hid) private var hid
    @Environment(\.scenePhase) private var scenePhase
    @State private var mods: KeyboardModifiers = []
    @State private var isCapsLockOn = false
    /// Keys currently down, so a release reports the union of what is left pressed
    /// instead of clearing the whole keyboard.
    @State private var heldKeys: Set<Keycode> = []
    /// Fingers on the key surface, shared with every per-key touch layer. One instance for
    /// the life of the page, held in `@StateObject` rather than `@State`: `@State` would
    /// keep the object alive just as well, but it does not subscribe to it, so the
    /// `@Published` count would reach nobody and the `onChange` below would stay dead code —
    /// measured, not assumed: a `@State`-held `ObservableObject` re-evaluated its body zero
    /// times as its value moved, while the same object in `@StateObject` re-evaluated it once
    /// per change. `@StateObject` subscribes, so `value` is what drives the safety net.
    @StateObject private var surfaceTouches = KeyTouchCount()

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height
            keyboard(size: geo.size, isLandscape: isLandscape)
        }
        .padding(.horizontal, keyHorizontalMargin)
        .padding(.vertical, 4)
        // The keys span the full width of the device. In landscape the horizontal safe
        // area is some 60pt a side, which left the keyboard as a narrow island with a
        // wide empty margin on either side of it. Only the horizontal edges are ignored:
        // the vertical insets stay, so the top row still clears the status bar and the
        // bottom row still clears the home indicator.
        .ignoresSafeArea(.container, edges: .horizontal)
        // last line of defence: nothing is touching the surface, so nothing may stay held.
        // This fires now that `KeyTouchCount` publishes its value; it can arrive at the same
        // moment as the surface layer's own report in `KeyCapTouchSurface`, and releasing
        // twice is harmless — `releaseAllKeys` leaves an empty keyboard alone, so the second
        // call is a no-op rather than a second clear.
        .onChange(of: surfaceTouches.value) { count in
            if count == 0 {
                releaseAllKeys()
            }
        }
        .onDisappear { releaseAllKeys() }
        .onChange(of: scenePhase) { phase in
            if phase != .active {
                releaseAllKeys()
            }
        }
    }

    // MARK: - Keyboard

    /// One six-row layout for both orientations, so a key sits in the same place
    /// whichever way the device is held.
    ///
    /// The rows are narrower in portrait than in landscape, so the keys are
    /// necessarily smaller there; they scale to fill the width exactly rather than
    /// scrolling. A scrolling surface was rejected on purpose: a scroll view delays
    /// touch delivery and its pan recogniser can cancel a touch that started on a
    /// key, which is the same class of interruption that used to leave keys latched.
    private func keyboard(size: CGSize, isLandscape: Bool) -> some View {
        let gap: CGFloat = isLandscape ? 5 : 4
        let totalRows: CGFloat = 6
        let availableHeight = size.height - (totalRows - 1) * gap
        let idealKeyHeight = availableHeight / totalRows
        // Keys stop at `maximumKeyHeight` so the trackpad can have the rest, but a strip
        // left over that is too shallow for the trackpad would just be dead space above
        // the home indicator; the keys take it back instead. This is where the height
        // freed by the removed title bar ends up on a device with no room for a trackpad.
        let leftoverForTrackpad = availableHeight - totalRows * maximumKeyHeight
        let keyHeight = max(
            minimumKeyHeight,
            idealKeyHeight > maximumKeyHeight && leftoverForTrackpad < trackpadMinimumHeight
                ? idealKeyHeight
                : min(maximumKeyHeight, idealKeyHeight)
        )

        return keyboardLayout(
            rows: [
                (row0, 15.0),
                (row1, 15.0),
                (row2, 15.0),
                (row3, 15.0),
                (row4, 15.0),
                (row5, 15.0)
            ],
            size: size,
            gap: gap,
            height: keyHeight,
            isCompact: !isLandscape
        )
    }

    /// Keys pinned to the top; a trackpad fills the leftover below when there is room for one.
    private func keyboardLayout(
        rows: [([FullKeyCap], CGFloat)],
        size: CGSize,
        gap: CGFloat,
        height: CGFloat,
        isCompact: Bool
    ) -> some View {
        let rowsHeight = CGFloat(rows.count) * height + CGFloat(max(rows.count - 1, 0)) * gap
        let leftover = size.height - rowsHeight

        return KeyCapTouchSurface(touches: surfaceTouches, onAllTouchesEnded: releaseAllKeys) {
            VStack(spacing: gap) {
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    keyRow(
                        row.0,
                        row: rowIndex,
                        width: size.width,
                        gap: gap,
                        height: height,
                        totalWeight: row.1,
                        isCompact: isCompact
                    )
                }
                if leftover >= trackpadMinimumHeight {
                    TrackpadPanel(hid: hid, showsControls: false)
                        .frame(maxHeight: .infinity)
                        .padding(.bottom, trackpadBottomInset)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        // The press bubbles are drawn over the whole keyboard instead of inside the row
        // that owns the cap: a row clips to its own bounds, and the top row sits against
        // the top edge of the keyboard, so its bubble has to reach above that row.
        .overlayPreferenceValue(KeyPressBubblePreference.self) { bubbles in
            KeyPressBubbleOverlay(bubbles: bubbles)
        }
    }

    private func keyRow(
        _ keys: [FullKeyCap],
        row rowIndex: Int,
        width: CGFloat,
        gap: CGFloat,
        height: CGFloat,
        totalWeight: CGFloat,
        isCompact: Bool
    ) -> some View {
        let gaps = gap * CGFloat(max(keys.count - 1, 0))
        let unit = max(0, (width - gaps) / totalWeight)

        return HStack(spacing: gap) {
            ForEach(Array(keys.enumerated()), id: \.offset) { column, key in
                FullKeyCapButton(
                    id: KeyCapID(row: rowIndex, column: column),
                    key: key,
                    isCompact: isCompact,
                    isArmed: isKeyArmed(key),
                    isShiftActive: isShiftActive,
                    surfaceTouches: surfaceTouches,
                    onPress: { handlePress(key) },
                    onRelease: { handleRelease(key) }
                )
                .frame(width: max(0, unit * key.weight), height: height)
            }
        }
    }

    private var isShiftActive: Bool {
        mods.contains(.leftShift) || mods.contains(.rightShift) || isCapsLockOn
    }

    private func isKeyArmed(_ key: FullKeyCap) -> Bool {
        switch key.action {
        case let .modifier(mod):
            return mods.contains(mod)
        case .capsLock:
            return isCapsLockOn
        case .key:
            return false
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
        heldKeys.insert(code)
        sendHeldKeys()
    }

    /// Releases `code` while leaving any other held key down.
    private func keyUp(_ code: Keycode) {
        heldKeys.remove(code)
        sendHeldKeys()
    }

    /// Drops every held key and clears the host, e.g. when the page goes away or the app backgrounds.
    private func releaseAllKeys() {
        guard !heldKeys.isEmpty else { return }
        heldKeys.removeAll()
        hid.keyUp()
    }

    private func sendHeldKeys() {
        var effectiveMods = mods
        if isCapsLockOn {
            for key in heldKeys where isLetter(key) {
                effectiveMods.insert(.leftShift)
            }
        }
        hid.sendKeyboard(KeyboardReport(modifiers: effectiveMods, keys: Array(heldKeys).sorted { $0.rawValue < $1.rawValue }))
    }

    private func toggleCapsLock() {
        isCapsLockOn.toggle()
        hid.tap(.capsLock, modifiers: mods)
    }

    private func toggleMod(_ mod: KeyboardModifiers) {
        if mods.contains(mod) {
            mods.subtract(mod)
        } else {
            mods.insert(mod)
        }
    }

    private func isLetter(_ key: Keycode) -> Bool {
        switch key {
        case .a, .b, .c, .d, .e, .f, .g, .h, .i, .j, .k, .l, .m,
             .n, .o, .p, .q, .r, .s, .t, .u, .v, .w, .x, .y, .z:
            return true
        default:
            return false
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
        // key down, and on macOS it must not take the cap's drag gesture either
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

    var body: some View {
        ZStack {
            // the cap's fill is translucent, so a bubble needs an opaque backing of its
            // own: otherwise the rows behind the lifted key would show straight through
            RoundedRectangle(cornerRadius: bubbleCornerRadius)
                .fill(.background)
            RoundedRectangle(cornerRadius: bubbleCornerRadius)
                .fill(bubble.isArmed ? Color.accentColor : groupFill)
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

    /// Held only while a finger on this cap is down. `key` stays a value type so a key can
    /// never be stale across the `@State` snapshot, but the flag is dropped the moment the
    /// view carrying it goes away — see `releaseIfStranded`.
    @State private var pressedKey: FullKeyCap?

    var body: some View {
        ZStack {
            #if os(iOS)
                KeyCapTouchView(
                    touches: surfaceTouches,
                    onFirstTouch: press,
                    onLastTouch: release
                )
            #endif
            RoundedRectangle(cornerRadius: 6)
                .fill(isArmed ? Color.accentColor : groupFill)
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
        #if !os(iOS)
            // macOS keeps the previous press/release gesture: this page only sees touch
            // input on iOS, where the layer inside the ZStack replaces it.
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in press() }
                    .onEnded { _ in release() }
            )
        #endif
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
        FullKeyboardView()
    }
#endif
