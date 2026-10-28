import SwiftUI

/// The input tab: one full-screen MacBook keyboard and one full-screen
/// multi-touch trackpad, with the page switch pinned to the bottom.
///
/// The tab owns the release coordinator, so leaving the page, leaving the app,
/// losing the host or losing the HID service all release keyboard and pointer
/// state through the same idempotent path.
struct InputView: View {
    let goToSetup: () -> Void

    @Environment(\.hid) private var hid
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appTheme) private var appTheme
    @AppStorage(AppSettings.developerModeKey) private var developerMode = false
    @AppStorage(AppSettings.inputPageKey) private var selectedPageRawValue = InputPage.keyboard.rawValue
    @StateObject private var releases = InputReleaseCoordinator()

    @MainActor
    init(goToSetup: @escaping () -> Void) {
        self.goToSetup = goToSetup
    }

    private var selectedPage: InputPage {
        InputPage(rawValue: selectedPageRawValue) ?? .keyboard
    }

    var body: some View {
        Group {
            if hid.isActive || developerMode {
                content
            } else {
                NotConnectedView(icon: "keyboard", goToSetup: goToSetup)
            }
        }
        .onChange(of: hid.isActive) { isActive in
            if !isActive {
                releases.releaseAll(using: hid)
            }
        }
        .onChange(of: hid.isConnected) { isConnected in
            if !isConnected {
                releases.releaseAll(using: hid)
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active {
                releases.releaseAll(using: hid)
            }
        }
        .onDisappear {
            releases.releaseAll(using: hid)
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            pageContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            pageSwitcher
        }
        .background(appTheme.pageBackground)
    }

    @ViewBuilder
    private var pageContent: some View {
        switch selectedPage {
        case .keyboard:
            FullKeyboardView(releases: releases)
        case .trackpad:
            TrackpadPanel(hid: hid, releases: releases)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 6)
        }
    }

    private var pageSwitcher: some View {
        HStack(spacing: ChipMetrics.rowSpacing) {
            ForEach(InputPage.allCases) { page in
                Button {
                    select(page)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: page.icon)
                            .font(.system(size: ChipMetrics.iconSize, weight: .semibold))
                        Text(page.title)
                            .font(.system(size: ChipMetrics.iconSize, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .padding(.vertical, ChipMetrics.labelPadding + 2)
                    .padding(.horizontal, ChipMetrics.labelPadding)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: ChipMetrics.cornerRadius)
                            .fill(selectedPage == page ? Color.accentColor : appTheme.controlFill)
                    )
                    .foregroundColor(selectedPage == page ? .white : .primary)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedPage == page ? .isSelected : [])
            }
        }
        .padding(.horizontal, ChipMetrics.pageHorizontalPadding)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    /// Releasing before the animation is the contract: the other page must not
    /// inherit a held key, a held pointer button or a live two-finger gesture.
    private func select(_ page: InputPage) {
        guard page != selectedPage else { return }
        Haptics.tap(from: .keyboard)
        releases.releaseAll(using: hid)
        withAnimation(.easeInOut(duration: 0.18)) {
            selectedPageRawValue = page.rawValue
        }
    }
}

struct NotConnectedView: View {
    let icon: String
    let goToSetup: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 56))
                .foregroundColor(.secondary)
            Text(L10n.Input.notConnectedTitle)
                .font(.title2.weight(.semibold))
            Text(L10n.Input.notConnectedMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button(L10n.Input.openSetup, action: goToSetup)
                .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if DEBUG
    #Preview {
        InputView(goToSetup: {})
    }
#endif
