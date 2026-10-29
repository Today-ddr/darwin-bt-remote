import SwiftUI
import UIKit

@main
struct BTRemoteApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var lowEnergy = HIDPeripheral()
    @StateObject private var central = HIDCentral()

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
            AppSettings.fullscreenKeyboardKey: true,
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
        HIDInput.make(lowEnergy: lowEnergy, central: central)
    }

    /// The scene leaving the foreground suspends the peripheral, and coming back resumes
    /// only what this app itself suspended, so a Stop Advertising the user tapped is not
    /// undone by backgrounding the app and coming back.
    ///
    /// Suspending takes the peripheral down and ends the links with it. Stopping
    /// advertising alone is not enough: a host that was already connected keeps its link
    /// through the background, and a link that outlives the foreground is exactly what
    /// keeps the radio busy and wakes a paired host. A host that is dropped this way is
    /// rediscoverable — the app advertises again on the way back in — and the user's own
    /// state survives it.
    ///
    /// `isAdvertising` is the only thing consulted for whether to suspend, rather than
    /// `autoAdvertise` or `isHIDServiceAdded`: it is what says a host could really find
    /// us. The resume is gated on `didSuspendPeripheral` instead, which is what keeps it
    /// a resume rather than a way to start advertising.
    private func _scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .active:
            guard didSuspendPeripheral else { return }
            didSuspendPeripheral = false
            lowEnergy.resume()
        case .inactive, .background:
            // a lock or the app switcher passes through `.inactive` and may report only
            // that, so both mean the app is no longer in front, which is when it has to
            // let go of its hosts. Suspending is idempotent, so a second phase of the
            // same departure can reach here with nothing left to do.
            guard lowEnergy.isOnTheAir else { return }
            lowEnergy.suspend()
            didSuspendPeripheral = true
        @unknown default:
            break
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(lowEnergy)
                .environmentObject(central)
                .environmentObject(deviceNames)
                .environment(\.hid, hid)
                .environment(\.appTheme, theme)
                .preferredColorScheme(theme.preferredColorScheme)
                .onAppear {
                    central.start()
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
