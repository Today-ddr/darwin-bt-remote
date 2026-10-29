import SwiftUI

struct ContentView: View {
    @State private var tab = AppTab.setup

    @Environment(\.hid) private var hid
    @Environment(\.appTheme) private var appTheme

    var body: some View {
        rootTabs
            .onChange(of: hid.isConnected) { connected in
                guard connected else { return }
                tab = .input
            }
            .onChange(of: tab) { newTab in
                OrientationController.apply(for: newTab)
            }
            .onAppear {
                OrientationController.apply(for: tab)
            }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            SetupView()
                .tabItem { Label(L10n.Tab.setup, systemImage: "gearshape") }
                .tag(AppTab.setup)
            InputView(
                goToSetup: { tab = .setup },
                goToSettings: { tab = .settings }
            )
            .tabItem { Label(L10n.Tab.input, systemImage: "keyboard") }
            .tag(AppTab.input)
            SettingsView()
                .tabItem { Label(L10n.Tab.settings, systemImage: "slider.horizontal.3") }
                .tag(AppTab.settings)
        }
        .nativeTabBarHidden()
    }

    private var rootTabs: some View {
        GeometryReader { proxy in
            let isLandscape = proxy.size.width > proxy.size.height
            let showsDock = DockVisibilityPolicy.showsDock(
                isLandscape: isLandscape,
                selectedTab: tab
            )
            tabs
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if showsDock {
                        AppDock(selection: $tab)
                    }
                }
                .animation(.easeInOut(duration: 0.18), value: showsDock)
                .background(appTheme.pageBackground.ignoresSafeArea())
        }
    }
}

#if DEBUG
    #Preview {
        ContentView()
            .environmentObject(HIDPeripheral())
            .environmentObject(HIDCentral())
            .environmentObject(DeviceNameStore())
    }
#endif
