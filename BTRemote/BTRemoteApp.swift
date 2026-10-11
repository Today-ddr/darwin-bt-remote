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
