import SwiftUI

struct GuideView: View {
    @AppStorage(AppSettings.advertisedNameKey) private var advertisedName = L10n.Bluetooth.advertisedName

    var body: some View {
        Form {
            Section(header: header(L10n.Setup.fromDevice, L10n.Setup.connectFromTargetDevice), footer: fromDeviceFooter) {
                step("1.circle", L10n.Setup.fromDeviceStep1)
                step("2.circle", Text(verbatim: L10n.Setup.fromDeviceStep2(advertisedName)))
                step("3.circle", L10n.Setup.fromDeviceStep3)
            }
        }
        .navigationTitle(L10n.Setup.lowEnergyGuide)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var fromDeviceFooter: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Setup.troubleshooting)
            locationHint
        }
    }

    private var locationHint: some View {
        Text(L10n.Setup.findGuideHint)
    }

    private func step(_ icon: String, _ text: LocalizedStringKey) -> some View {
        step(icon, Text(text))
    }

    private func step(_ icon: String, _ text: Text) -> some View {
        Label { text } icon: { Image(systemName: icon) }
    }

    private func header(_ title: LocalizedStringKey, _ subtitle: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(subtitle).font(.caption).foregroundColor(.secondary).textCase(nil)
        }
    }
}
