import Combine
import SwiftUI
import UIKit

@main
struct BTRemoteApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var lowEnergy = HIDPeripheral()

    /// Declared outside any tab on purpose: advertising is what wakes paired
    /// hosts, so it does not belong to whichever page is on screen. Off unless
    /// the user turns it on — the app stays silent until asked.
    @AppStorage(AppSettings.autoAdvertiseKey) private var autoAdvertise = false

    @StateObject private var deviceNames = DeviceNameStore()
    @AppStorage(AppSettings.colorSchemeKey) private var selectedTheme = "system"

    /// Read at the app level rather than inside a page: advertising is not a property of
    /// whichever tab is on screen, and the pages have no say over whether the app is in
    /// front.
    @Environment(\.scenePhase) private var scenePhase

    /// Whether this app suspended its own peripheral when the scene stopped being active.
    ///
    /// What it separates is a suspension from the user's own Stop Advertising: only a
    /// suspension is resumed, so the button is not undone by leaving the app. It lives
    /// here rather than in `HIDPeripheral` because the scene's phase is the only thing
    /// that sets it and this is what observes the phase. The window is one, so one bit is
    /// enough, and it is never persisted: a relaunch starts with it clear, which is also
    /// what makes the launch path the only thing that decides what a relaunch advertises.
    @State private var didSuspendPeripheral = false

    private var theme: AppTheme {
        AppTheme(storedValue: selectedTheme)
    }

    init() {
        UITabBar.appearance().isHidden = true
        UserDefaults.standard.register(defaults: [
            AppSettings.useServiceChangedKey: true,
            AppSettings.colorSchemeKey: AppTheme.system.rawValue,
            AppSettings.inputPageKey: InputPage.keyboard.rawValue,
            // Haptics read raw UserDefaults, so the on-by-default state has to be
            // registered here — an @AppStorage default alone is invisible to them.
            AppSettings.hapticsEnabledKey: true,
            AppSettings.hapticsTrackpadKey: true,
            AppSettings.hapticsKeyboardKey: true,
            AppSettings.hapticsScrollKey: true,
            AppSettings.hapticsIntensityKey: Haptics.Intensity.medium.rawValue,
            AppSettings.doubleTapDragKey: true,
            AppSettings.longPressDragKey: true
        ])
    }

    private var hid: HIDInput {
        HIDInput.make(lowEnergy: lowEnergy)
    }

    /// The scene entering the background suspends the peripheral, and coming back resumes
    /// only what this app itself suspended, so a Stop Advertising the user tapped is not
    /// undone by backgrounding the app and coming back.
    ///
    /// Only `.background` is a departure. `.inactive` is what a pull-down of Control Center,
    /// a system alert, the app switcher, or an incoming call produces while the app is
    /// still on screen; tearing down every host for one of those would drop the connection
    /// for something the user did not leave the app for. Actually going to the Home screen
    /// or another app passes through `.inactive` into `.background`, which is where the
    /// teardown happens.
    ///
    /// Suspending takes the peripheral down and ends the links with it. Stopping
    /// advertising alone is not enough: a host that was already connected keeps its link
    /// through the background, and a link that outlives the foreground is exactly what
    /// keeps the radio busy and wakes a paired host. A host that is dropped this way is
    /// rediscoverable — the app advertises again on the way back in — and the user's own
    /// state survives it.
    ///
    /// `isOnTheAir` is what decides whether there is anything to suspend: it covers the
    /// install window and a live service whose advertising the user already stopped, not
    /// just `isAdvertising`. The resume is gated on `didSuspendPeripheral`, which is what
    /// keeps it a resume rather than a way to start advertising.
    private func _scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .active:
            guard didSuspendPeripheral else { return }
            didSuspendPeripheral = false
            lowEnergy.resume()
        case .background:
            guard lowEnergy.isOnTheAir else { return }
            lowEnergy.suspend()
            didSuspendPeripheral = true
        case .inactive:
            // not a departure: Control Center, a system dialog or a call can leave the app
            // inactive while it is still in front. The links stay until `.background`.
            break
        @unknown default:
            break
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(lowEnergy)
                .environmentObject(deviceNames)
                .environment(\.hid, hid)
                .environment(\.appTheme, theme)
                .preferredColorScheme(theme.preferredColorScheme)
                .onAppear {
                    // the HID battery reflects the device's own level; enabling monitoring
                    // also makes the change notification below arrive
                    lowEnergy.refreshBatteryLevel()
                    // with the preference off nothing is advertised, but the radio is
                    // still read so Setup shows the real Bluetooth state instead of
                    // "unknown" — `observeState` installs no services and starts no
                    // advertising, so the app stays silent either way
                    if autoAdvertise {
                        lowEnergy.start()
                    } else {
                        lowEnergy.observeState()
                    }
                }
                // foreground-only battery tracking: no background task, and the system
                // posts this only while monitoring is enabled
                .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)) { _ in
                    lowEnergy.refreshBatteryLevel()
                }
                // a host that finds this app wakes to a radio that is still advertising, and
                // a link that outlives the foreground keeps waking it, so neither outlives
                // the foreground: leaving it suspends the peripheral and takes the links
                // with it. A force-quit runs none of this, and the launch path above is the
                // only thing that decides what relaunching does — that is `autoAdvertise`,
                // not this.
                .onChange(of: scenePhase) { phase in
                    _scenePhaseChanged(phase)
                }
        }
    }
}
