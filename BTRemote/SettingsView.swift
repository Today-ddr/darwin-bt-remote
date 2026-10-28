import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var lowEnergy: HIDPeripheral
    @EnvironmentObject private var names: DeviceNameStore
    @Environment(\.hid) private var hid
    @State private var showReset = false
    @AppStorage(AppSettings.colorSchemeKey) private var selectedThemeRaw = AppTheme.system.rawValue
    @AppStorage(AppSettings.fullscreenKeyboardKey) private var fullscreenKeyboard = true
    @AppStorage(AppSettings.touchpadSensitivityKey) private var touchpadSensitivity = AppSettings.defaultPointerSensitivity
    @AppStorage(AppSettings.scrollSensitivityKey) private var scrollSensitivity = AppSettings.defaultScrollSensitivity
    @AppStorage(AppSettings.developerModeKey) private var developerMode = false
    @AppStorage(AppSettings.useServiceChangedKey) private var forceServiceChanged = true
    @AppStorage(AppSettings.hasSeenWelcomeKey) private var hasSeenWelcome = false
    @AppStorage(AppSettings.hapticsEnabledKey) private var hapticsEnabled = true
    @AppStorage(AppSettings.hapticsTrackpadKey) private var hapticsTrackpad = true
    @AppStorage(AppSettings.hapticsKeyboardKey) private var hapticsKeyboard = true
    @AppStorage(AppSettings.hapticsScrollKey) private var hapticsScroll = true
    @AppStorage(AppSettings.hapticsIntensityKey) private var hapticsIntensity = Haptics.Intensity.medium.rawValue
    /// off by default: advertising is what wakes paired hosts, so it waits to be asked for
    @AppStorage(AppSettings.autoAdvertiseKey) private var autoAdvertise = false

    private var selectedTheme: AppTheme {
        AppTheme(storedValue: selectedThemeRaw)
    }

    var body: some View {
        NavigationView {
            form.navigationTitle(L10n.Tab.settings)
        }
        .navigationViewStyle(.stack)
    }

    private var form: some View {
        Form {
            Section {
                Picker(L10n.Settings.appearance, selection: $selectedThemeRaw) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.title).tag(theme.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text(L10n.Settings.appearance)
            } footer: {
                if selectedTheme == .oled {
                    Text(L10n.Settings.oledHint)
                }
            }
            Section {
                Toggle(L10n.Settings.fullScreenKeyboard, isOn: $fullscreenKeyboard)
            } header: {
                Text(L10n.Settings.keyboard)
            } footer: {
                Text(L10n.Settings.fullScreenKeyboardHint)
            }
            Section(header: Text(L10n.Settings.trackpad)) {
                sensitivityRow(L10n.Settings.trackingSpeed, value: $touchpadSensitivity, range: AppSettings.pointerSensitivityRange)
                sensitivityRow(L10n.Settings.scrollSpeed, value: $scrollSensitivity, range: AppSettings.scrollSensitivityRange)
                NavigationLink {
                    TrackpadGestureSettingsView()
                } label: {
                    Label(L10n.Gesture.sectionTitle, systemImage: "hand.draw")
                }
            }
            Section(header: Text(L10n.Settings.haptics), footer: Text(L10n.Settings.hapticsHint)) {
                Toggle(L10n.Settings.hapticsEnabled, isOn: $hapticsEnabled)
                if hapticsEnabled {
                    Picker(L10n.Settings.hapticsIntensity, selection: $hapticsIntensity) {
                        Text(L10n.Settings.hapticsIntensityLight).tag(Haptics.Intensity.light.rawValue)
                        Text(L10n.Settings.hapticsIntensityMedium).tag(Haptics.Intensity.medium.rawValue)
                        Text(L10n.Settings.hapticsIntensityStrong).tag(Haptics.Intensity.strong.rawValue)
                    }
                    .pickerStyle(.segmented)
                    Toggle(L10n.Settings.hapticsTrackpad, isOn: $hapticsTrackpad)
                    Toggle(L10n.Settings.hapticsScroll, isOn: $hapticsScroll)
                        .disabled(!hapticsTrackpad)
                    Toggle(L10n.Settings.hapticsKeyboard, isOn: $hapticsKeyboard)
                }
            }
            .onChange(of: hapticsEnabled) { enabled in
                if enabled {
                    Haptics.prepare()
                }
            }
            .onChange(of: hapticsIntensity) { _ in
                // The new level needs a fresh generator, so warm it up here
                // rather than paying the spin-up cost on the first tap.
                Haptics.prepare()
            }
            Section(header: Text(L10n.Settings.connection), footer: Text(L10n.Settings.autoAdvertiseHint)) {
                Toggle(L10n.Settings.autoAdvertise, isOn: $autoAdvertise)
            }
            Section(footer: Text(L10n.Settings.forceServiceChangedHint)) {
                Toggle(L10n.Settings.forceServiceChanged, isOn: $forceServiceChanged)
                    .onChange(of: forceServiceChanged) {
                        if $0 {
                            lowEnergy.scheduleServiceChanged()
                        }
                    }
            }
            Section(header: Text(L10n.Settings.advanced)) {
                Toggle(L10n.Settings.developerMode, isOn: $developerMode)
                Link(destination: AppSettings.repoURL) {
                    Label(L10n.Settings.sourceCode, systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }
            if developerMode, hid.isActive {
                batterySection
            }
            resetSection
        }
        .confirmationDialog(L10n.Settings.resetConfirm, isPresented: $showReset, titleVisibility: .visible) {
            Button(L10n.Settings.reset, role: .destructive) { _resetAll() }
        }
    }

    private var resetSection: some View {
        Section {
            Button(role: .destructive) { showReset = true } label: {
                Label(L10n.Settings.reset, systemImage: "trash")
            }
        }
    }

    private func _resetAll() {
        names.clear()
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        hasSeenWelcome = false
    }

    private var batterySection: some View {
        Section(header: Text(L10n.Section.battery)) {
            Slider(
                value: Binding(
                    get: { Double(hid.batteryLevel) },
                    set: { hid.updateBattery(UInt8($0)) }
                ),
                in: 0 ... 100,
                step: 1
            )
            HStack {
                Text(L10n.Battery.level)
                Spacer()
                Text(Double(hid.batteryLevel) / 100, format: .percent.precision(.fractionLength(0)))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func sensitivityRow(_ title: LocalizedStringKey, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(value.wrappedValue, format: .number.precision(.fractionLength(1)))
                    .foregroundColor(.secondary)
                    + Text(verbatim: "×").foregroundColor(.secondary)
            }
            Slider(value: value, in: range, step: 0.1)
        }
    }
}

#if DEBUG
    #Preview {
        SettingsView()
            .environmentObject(HIDPeripheral())
            .environmentObject(HIDCentral())
            .environmentObject(DeviceNameStore())
    }
#endif
