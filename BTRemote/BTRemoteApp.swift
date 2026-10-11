import SwiftUI

#if os(macOS)
    enum TransportMode: String, CaseIterable, Codable {
        case classic
        case lowEnergy

        static let defaultMode: TransportMode = .lowEnergy
    }
#endif

@main
struct BTRemoteApp: App {
    #if os(iOS)
        @StateObject private var lowEnergy = HIDPeripheral()
        @StateObject private var central = HIDCentral()
    #else
        @StateObject private var lowEnergy = HIDPeripheral()
        @StateObject private var central = HIDCentral()
        @StateObject private var classic = HIDClassicDevice()
        @AppStorage("BTRemote.macTransportMode") private var modeRaw: String = TransportMode.defaultMode.rawValue
    #endif

    /// Declared outside the platform branches on purpose: advertising is what wakes paired
    /// hosts, so which platform ignores this preference is not a detail that can differ
    /// between them. Off unless the user turns it on — the app stays silent until asked.
    @AppStorage(AppSettings.autoAdvertiseKey) private var autoAdvertise = false

    @StateObject private var deviceNames = DeviceNameStore()
    @AppStorage(AppSettings.colorSchemeKey) private var selectedTheme = "system"

    #if os(iOS)
        /// Read at the app level rather than inside a page: advertising is not a property of
        /// whichever tab is on screen, and the pages have no say over whether the app is in
        /// front. `FullKeyboardView` observes the same value for its own key-release logic;
        /// that is about a finger being interrupted, not about this, and stays as it is.
        @Environment(\.scenePhase) private var scenePhase

        /// Whether this app suspended its own advertising when the scene stopped being active.
        ///
        /// What it separates is a suspension from the user's own Stop Advertising: only a
        /// suspension is resumed, so the button is not undone by leaving the app. It lives
        /// here rather than in `HIDPeripheral` because the scene's phase is the only thing
        /// that sets it and this is what observes the phase. The peripheral keeps no opinion
        /// about why it was stopped, which is what keeps this bit from colliding with
        /// `isHIDServiceAllowed` ("services may be installed") and from being mistaken for
        /// advertising that dropped on its own — a Bluetooth teardown is not resumed either.
        /// The window is one, so one bit is enough, and it is never persisted: a relaunch
        /// starts with it clear.
        @State private var suspendedAdvertising = false
    #endif

    private var preferredColorScheme: ColorScheme? {
        switch selectedTheme {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    init() {
        UserDefaults.standard.register(defaults: [
            AppSettings.useServiceChangedKey: true,
            // Haptics read raw UserDefaults, so the on-by-default state has to be
            // registered here — an @AppStorage default alone is invisible to them.
            AppSettings.hapticsEnabledKey: true,
            AppSettings.hapticsTrackpadKey: true,
            AppSettings.hapticsKeyboardKey: true,
            AppSettings.hapticsScrollKey: true,
            AppSettings.hapticsIntensityKey: Haptics.Intensity.strong.rawValue
        ])
    }

    private var hid: HIDInput {
        #if os(macOS)
            return HIDInput.make(lowEnergy: lowEnergy, central: central, classic: classic, classicMode: currentMode == .classic)
        #else
            return HIDInput.make(lowEnergy: lowEnergy, central: central)
        #endif
    }

    #if os(iOS)
        /// The scene leaving the foreground stops advertising; coming back resumes only what
        /// this app itself stopped, so a Stop Advertising the user tapped is not undone by
        /// backgrounding the app and coming back.
        ///
        /// `isAdvertising` is the only thing consulted, rather than `autoAdvertise` or
        /// `isHIDServiceAdded`: it is what says a host could really find us, and it also keeps
        /// the resume from becoming a back door into advertising at launch, since it is false
        /// until advertising actually starts. Resuming calls `start()`, the same way in the
        /// launch path uses, and issues an intent rather than a fact: a manager coming up or a
        /// service being installed both finish in a callback, so advertising is never claimed
        /// here — `peripheralManagerDidStartAdvertising` is what settles that, exactly as it
        /// does after a tap in Setup. Nothing is narrowed to a smaller call, because `start()`
        /// is already idempotent and the narrower pieces are private. A host that is still
        /// subscribed keeps its link either way: only advertising stops, so a bounded
        /// suspension does not have to be an actual Bluetooth restart to bring the app back,
        /// and the radio is never left unreadable to Setup.
        private func _scenePhaseChanged(_ phase: ScenePhase) {
            switch phase {
            case .active:
                guard suspendedAdvertising else { return }
                suspendedAdvertising = false
                lowEnergy.start()
            case .inactive, .background:
                // a lock or the app switcher passes through `.inactive` and may report only
                // that, so both mean the app is no longer in front, which is when it has to
                // stop. Stopping is idempotent, so a second phase of the same departure can
                // reach here with nothing left to do.
                guard lowEnergy.isAdvertising else { return }
                lowEnergy.stop()
                suspendedAdvertising = true
            @unknown default:
                break
            }
        }
    #endif

    var body: some Scene {
        WindowGroup {
            #if os(iOS)
                ContentView()
                    .environmentObject(lowEnergy)
                    .environmentObject(central)
                    .environmentObject(deviceNames)
                    .environment(\.hid, hid)
                    .preferredColorScheme(preferredColorScheme)
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
                    // a host that finds this app wakes to a radio that is still advertising, so
                    // advertising does not outlive the foreground. A force-quit runs none of
                    // this, and the launch path above is the only thing that decides what
                    // relaunching does — that is `autoAdvertise`, not this.
                    .onChange(of: scenePhase) { phase in
                        _scenePhaseChanged(phase)
                    }
            #else
                ContentView()
                    .environmentObject(lowEnergy)
                    .environmentObject(central)
                    .environmentObject(classic)
                    .environmentObject(deviceNames)
                    .environment(\.macTransport, currentMode)
                    .environment(\.hid, hid)
                    .preferredColorScheme(preferredColorScheme)
                    .onAppear { _onAppear() }
                    .onChange(of: modeRaw) { _ in _modeChanged() }
                // No scene-phase rule here, on purpose. `scenePhase` on macOS is the
                // window's activation, which is whenever another app comes to the front —
                // and handing input to another app is this app's job there: the direct
                // input capture is built around not being frontmost, and the classic
                // transport does not advertise at all, so stopping on `.inactive` would
                // cut off an app that is still doing exactly what it was asked to. The
                // rule also has nothing to hold on to: `isAdvertising` is false while the
                // classic service is published, so a backgrounded window would silence the
                // wrong backend and skip the right one. The iOS rule is about the app
                // being hidden; on macOS being frontmost is not the same as being usable,
                // so advertising keeps the launch path it has today.
            #endif
        }
    }

    #if os(macOS)
        private var currentMode: TransportMode {
            TransportMode(rawValue: modeRaw) ?? .defaultMode
        }

        private func _onAppear() {
            switch currentMode {
            case .classic:
                classic.start()
            case .lowEnergy:
                // the launch path honours the preference exactly as the iOS branch does.
                // With it off, `observeState` still brings the radio up to read it — without
                // it the Setup page would read `.unknown` as Bluetooth being off and refuse
                // its own Start Advertising button. Services and advertising come only from
                // `start`. `central.start()` is a different role — scanning and connecting
                // to other people's devices — so launching it is not advertising and is
                // left as it was.
                if autoAdvertise {
                    lowEnergy.start()
                } else {
                    lowEnergy.observeState()
                }
                central.start()
            }
        }

        private func _modeChanged() {
            // tear down the previously-active backend to prevent race
            lowEnergy.stop()
            classic.stop()

            switch currentMode {
            case .classic:
                classic.start()
            case .lowEnergy:
                // switching mode is an explicit act by the user, so the peripheral comes up
                // with the mode they chose: they are in Setup, looking at the mode picker,
                // and a mode that comes up inert reads as the switch having failed. The
                // preference governs what the app does unprompted at launch, not what it
                // does when it is told to change.
                lowEnergy.start()
                central.start()
            }
        }
    #endif
}

#if os(macOS)
    private struct MacTransportKey: EnvironmentKey {
        static let defaultValue: TransportMode = .defaultMode
    }

    extension EnvironmentValues {
        var macTransport: TransportMode {
            get { self[MacTransportKey.self] }
            set { self[MacTransportKey.self] = newValue }
        }
    }
#endif
