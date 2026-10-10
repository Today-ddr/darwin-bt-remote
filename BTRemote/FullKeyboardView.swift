import SwiftUI

/// Leftover height below the key rows under which a trackpad would be too cramped to use.
private let trackpadMinimumHeight: CGFloat = 80
/// Keeps the embedded touch surface clear of the home indicator and the swipe-up gesture.
private let trackpadBottomInset: CGFloat = 8

struct FullKeyboardView: View {
    @Environment(\.hid) private var hid
    @Environment(\.scenePhase) private var scenePhase
    @State private var mods: KeyboardModifiers = []
    @State private var isCapsLockOn = false
    /// Keys currently down, so a release reports the union of what is left pressed
    /// instead of clearing the whole keyboard.
    @State private var heldKeys: Set<Keycode> = []
    /// Fingers on the key surface, shared with every per-key touch layer.
    @State private var surfaceTouches = KeyTouchCount()

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height
            keyboard(size: geo.size, isLandscape: isLandscape)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        // last line of defence: nothing is touching the surface, so nothing may stay held
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
        let keyHeight = min(52, max(28, availableHeight / totalRows))

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
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    keyRow(row.0, width: size.width, gap: gap, height: height, totalWeight: row.1, isCompact: isCompact)
                }
                if leftover >= trackpadMinimumHeight {
                    TrackpadPanel(hid: hid, showsControls: false)
                        .frame(maxHeight: .infinity)
                        .padding(.bottom, trackpadBottomInset)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func keyRow(
        _ keys: [FullKeyCap],
        width: CGFloat,
        gap: CGFloat,
        height: CGFloat,
        totalWeight: CGFloat,
        isCompact: Bool
    ) -> some View {
        let gaps = gap * CGFloat(max(keys.count - 1, 0))
        let unit = max(0, (width - gaps) / totalWeight)

        return HStack(spacing: gap) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                FullKeyCapButton(
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

private struct FullKeyCapButton: View {
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
            keyContent
                .foregroundColor(isArmed ? .white : .primary)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(pressedKey != nil ? 0.6 : 1)
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

    @ViewBuilder
    private var keyContent: some View {
        switch key.label {
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
