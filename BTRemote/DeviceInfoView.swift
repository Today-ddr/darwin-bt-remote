import SwiftUI

struct DeviceInfoView: View {
    let entry: DeviceEntry
    @EnvironmentObject private var names: DeviceNameStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView { content }
            .navigationViewStyle(.stack)
    }

    private var content: some View {
        Form {
            Section(header: Text(L10n.DeviceInfo.device)) {
                nameRow
                identifierRow(Text(verbatim: entry.id.uuidString))
            }
        }
        .navigationTitle(L10n.DeviceInfo.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(L10n.DeviceInfo.done) { dismiss() }
            }
        }
    }

    @ViewBuilder private var nameRow: some View {
        if entry.allowsNameEditing {
            NavigationLink {
                NameEditView(title: L10n.DeviceInfo.name, name: _deviceNameBinding)
            } label: {
                infoRow(L10n.DeviceInfo.name, Text(verbatim: entry.displayName))
            }
        } else {
            // a scanned peripheral is listed by the name it advertises, never by the stored
            // alias, so editing the name here would look like a no-op
            infoRow(L10n.DeviceInfo.name, Text(verbatim: entry.displayName))
        }
    }

    private func infoRow(_ label: LocalizedStringKey, _ value: Text) -> some View {
        HStack {
            Text(label)
            Spacer()
            value.foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func identifierRow(_ value: Text) -> some View {
        let label = Text(L10n.DeviceInfo.identifier)
        let detail = value.foregroundColor(.secondary).lineLimit(1).minimumScaleFactor(0.5).textSelection(.enabled)
        if #available(iOS 16, *) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    label
                    Spacer(minLength: 12)
                    detail
                }
                stackedRow(label, detail)
            }
        } else {
            stackedRow(label, detail)
        }
    }

    private func stackedRow(_ label: Text, _ detail: some View) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            label
            detail
        }
    }

    private var _deviceNameBinding: Binding<String> {
        Binding(
            get: { names.name(for: entry.id) ?? "" },
            set: { names.setName($0, for: entry.id) }
        )
    }
}

struct NameEditView: View {
    let title: LocalizedStringKey
    var footer: LocalizedStringKey?
    var maxLength: Int?
    @Binding var name: String
    var onCommit: () -> Void = {}

    @FocusState private var focused: Bool

    var body: some View {
        Form {
            Section(footer: _footer) {
                TextField(title, text: _clamped)
                    .focused($focused)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focused = true }
        .onDisappear(perform: onCommit)
    }

    @ViewBuilder private var _footer: some View {
        if let footer {
            Text(footer)
        }
    }

    private var _clamped: Binding<String> {
        Binding(
            get: { name },
            set: { new in name = maxLength.map { String(new.prefix($0)) } ?? new }
        )
    }
}
