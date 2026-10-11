import SwiftUI

/// Breathing room between the switch button and the media pill below it. `cellGap`
/// is the gap inside the remote's own panels; a slightly larger one keeps the
/// switch button reading as a separate control rather than as part of that group.
private let topGap: CGFloat = 8

private struct ConsumerButton {
    let report: ConsumerReport
    let icon: String
    let label: LocalizedStringKey

    init(_ key: ConsumerKey, _ icon: String, _ label: LocalizedStringKey) {
        report = ConsumerReport(key: key)
        self.icon = icon
        self.label = label
    }

    init(_ report: ConsumerReport, _ icon: String, _ label: LocalizedStringKey) {
        self.report = report
        self.icon = icon
        self.label = label
    }
}

struct RemoteView: View {
    let goToSetup: () -> Void

    @Environment(\.hid) private var hid
    @AppStorage(AppSettings.developerModeKey) private var developerMode = false
    @AppStorage(AppSettings.remoteModeKey) private var mode = RemoteMode.keyboard

    var body: some View {
        if hid.isActive || developerMode {
            controls
        } else {
            NotConnectedView(icon: "gamecontroller", goToSetup: goToSetup)
        }
    }

    private var controls: some View {
        VStack(spacing: topGap) {
            // The way back to the keyboard page. In the top row rather than a
            // toolbar so this page keeps the same shape as the keyboard page —
            // no title bar, switch control sitting above the content — and in
            // both orientations the D-pad column leaves this corner free.
            modeSwitchButton
            GeometryReader { geo in
                if geo.size.width > geo.size.height {
                    landscapeControls(geo.size)
                } else {
                    portraitControls(geo.size)
                }
            }
        }
        .padding(.horizontal, ChipMetrics.pageHorizontalPadding)
        .padding(.top, ChipMetrics.pageTopPadding)
        .padding(.bottom, 8)
    }

    /// Mirrors the keyboard page's switch button: the same corner radius, fill and
    /// icon + label, sized to the media pill rather than to a full-width row so it
    /// does not stretch across the remote. It carries a fill of its own because it
    /// sits on the page background, not on one of the remote's grouped panels.
    private var modeSwitchButton: some View {
        Button {
            Haptics.tap(from: .keyboard)
            withAnimation(.easeInOut(duration: 0.18)) {
                mode = .keyboard
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "keyboard")
                    .font(.system(size: ChipMetrics.iconSize, weight: .semibold))
                Text(L10n.Tab.keyboard)
                    .font(.system(size: ChipMetrics.iconSize, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.vertical, ChipMetrics.labelPadding)
            .padding(.horizontal, ChipMetrics.labelPadding)
            .background(
                RoundedRectangle(cornerRadius: ChipMetrics.cornerRadius)
                    .fill(groupFill)
            )
            .foregroundColor(.primary)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func portraitControls(_ size: CGSize) -> some View {
        let h = size.height
        return VStack(spacing: cellGap) {
            mediaPill.frame(height: h * 0.11)
            grid.frame(maxHeight: .infinity)
            bottomRow.frame(height: h * 0.11)
            dpad.frame(height: h * 0.42)
        }
        .frame(width: size.width, height: size.height)
    }

    private func landscapeControls(_ size: CGSize) -> some View {
        let h = size.height
        return HStack(spacing: cellGap * 2) {
            VStack(spacing: cellGap) {
                mediaPill.frame(height: h * 0.16)
                grid.frame(maxHeight: .infinity)
                bottomRow.frame(height: h * 0.16)
            }
            dpad.frame(width: min(h, size.width * 0.42))
        }
        .frame(width: size.width, height: size.height)
    }

    private var mediaPill: some View {
        HStack(spacing: 0) {
            consumerMember(.init(.rewind, "backward.fill", L10n.Media.rewind))
            consumerMember(.init(.playPause, "playpause.fill", L10n.Media.playPause))
            consumerMember(.init(.fastForward, "forward.fill", L10n.Media.fastForward))
        }
        .background(RoundedRectangle(cornerRadius: 26).fill(groupFill))
    }

    private var grid: some View {
        HStack(spacing: cellGap) {
            sideColumn(
                pill: { verticalPill(
                    .init(.volumeUp, "speaker.wave.3.fill", L10n.Media.volumeUp),
                    .init(.volumeDown, "speaker.wave.1.fill", L10n.Media.volumeDown)
                ) },
                tail: { consumerCircle(.init(.mute, "speaker.slash.fill", L10n.Media.mute)) }
            )
            numberColumn([(1, .digit1), (4, .digit4), (7, .digit7)])
            numberColumn([(2, .digit2), (5, .digit5), (8, .digit8)])
            numberColumn([(3, .digit3), (6, .digit6), (9, .digit9)])
            sideColumn(
                pill: { verticalPill(
                    .init(.channelUp, "plus", L10n.Remote.channelUp),
                    .init(.channelDown, "minus", L10n.Remote.channelDown)
                ) },
                tail: { consumerCircle(.init(.closedCaption, "captions.bubble", L10n.Remote.closedCaptions)) }
            )
        }
    }

    private func numberColumn(_ keys: [(Int, Keycode)]) -> some View {
        VStack(spacing: cellGap) {
            ForEach(keys, id: \.0) { number, key in
                numberCircle(number, key)
            }
        }
    }

    private func sideColumn(
        @ViewBuilder pill: @escaping () -> some View,
        @ViewBuilder tail: @escaping () -> some View
    ) -> some View {
        GeometryReader { g in
            VStack(spacing: cellGap) {
                pill().frame(height: (g.size.height - cellGap) * 2 / 3)
                tail().frame(height: (g.size.height - cellGap) / 3)
            }
            .frame(width: g.size.width, height: g.size.height)
        }
    }

    private func verticalPill(_ top: ConsumerButton, _ bottom: ConsumerButton) -> some View {
        VStack(spacing: 0) {
            consumerMember(top)
            consumerMember(bottom)
        }
        .background(Capsule().fill(groupFill))
    }

    private var bottomRow: some View {
        HStack(spacing: cellGap) {
            consumerCircle(.init(.acBack, "arrow.left", L10n.Remote.back))
            consumerCircle(.init(.acHome, "house.fill", L10n.Remote.home))
            numberCircle(0, .digit0)
            consumerCircle(.init(.menu, "list.bullet", L10n.Remote.menu))
            consumerCircle(.init(.power, "power", L10n.Remote.power))
        }
    }

    private var dpad: some View {
        DPadView(
            onPress: { hid.sendConsumer($0) },
            onRelease: { hid.sendConsumer(.zero) }
        )
    }

    private func consumerCircle(_ button: ConsumerButton) -> some View {
        HoldButton(
            onPress: { hid.sendConsumer(button.report) },
            onRelease: { hid.sendConsumer(.zero) },
            background: { Circle().fill(groupFill) },
            label: { Image(systemName: button.icon).font(.title3) }
        )
        .accessibilityLabel(button.label)
    }

    private func consumerMember(_ button: ConsumerButton) -> some View {
        HoldButton(
            onPress: { hid.sendConsumer(button.report) },
            onRelease: { hid.sendConsumer(.zero) },
            background: { Color.clear },
            label: { Image(systemName: button.icon).font(.title3) }
        )
        .accessibilityLabel(button.label)
    }

    private func numberCircle(_ number: Int, _ key: Keycode) -> some View {
        HoldButton(
            onPress: { hid.sendKeyboard(KeyboardReport(keys: [key])) },
            onRelease: { hid.sendKeyboard(.zero) },
            background: { Circle().fill(groupFill) },
            label: { Text(verbatim: "\(number)").font(.title3.weight(.medium)) }
        )
    }
}

#if DEBUG
    #Preview {
        RemoteView(goToSetup: {})
    }
#endif
