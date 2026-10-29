import SwiftUI

struct ContentView: View {
    @State private var tab = AppTab.setup

    @Environment(\.hid) private var hid
    @Environment(\.appTheme) private var appTheme
    @Environment(\.openURL) private var openURL
    @AppStorage(AppSettings.hasSeenWelcomeKey) private var hasSeenWelcome = false
    @AppStorage(AppSettings.fullscreenKeyboardKey) private var fullscreenKeyboard = true
    @AppStorage(AppSettings.inputPageKey) private var inputPage = InputPage.keyboard.rawValue
    @State private var showWelcome = false
    @State private var showGuide = false

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
                _onAppear()
                OrientationController.apply(for: tab)
            }
            .alert(L10n.Welcome.title, isPresented: $showWelcome) {
                Button(L10n.Welcome.viewGuide) {
                    hasSeenWelcome = true
                    showGuide = true
                }
                .keyboardShortcut(.defaultAction)
                Button(L10n.Setup.videoInstructions) { openURL(AppSettings.instructionsURL) }
            } message: {
                Text(L10n.Welcome.message)
            }
            .sheet(isPresented: $showGuide) { guideSheet }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            SetupView()
                .tabItem { Label(L10n.Tab.setup, systemImage: "gearshape") }
                .tag(AppTab.setup)
            InputView(goToSetup: { tab = .setup })
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
                hidesDockInLandscape: fullscreenKeyboard,
                isLandscape: isLandscape,
                selectedTab: tab,
                inputPageRawValue: inputPage
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

    private func _onAppear() {
        if !hasSeenWelcome {
            showWelcome = true
        }
    }

    private var guideSheet: some View {
        NavigationView { guideSheetContent }
            .navigationViewStyle(.stack)
    }

    private var guideSheetContent: some View {
        GuideView()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Action.done) { showGuide = false }
                }
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
