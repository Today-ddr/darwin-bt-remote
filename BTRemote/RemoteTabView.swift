import SwiftUI

enum RemoteMode: String {
    case keyboard, remote
}

struct RemoteTabView: View {
    let goToSetup: () -> Void

    @AppStorage(AppSettings.remoteModeKey) private var mode = RemoteMode.keyboard

    var body: some View {
        #if os(macOS)
            NavigationStack { content }
        #else
            NavigationView { content }
                .navigationViewStyle(.stack)
        #endif
    }

    /// No title bar on this page: the switcher row of whichever page is showing is its
    /// topmost element. Each page carries its own button for switching to the other one —
    /// `KeyboardView` adds a remote-page button to its page row, `RemoteView` puts a
    /// keyboard-page button above the media pill — and each writes the shared mode key.
    @ViewBuilder
    private var content: some View {
        switch mode {
        case .keyboard: KeyboardView(goToSetup: goToSetup)
        case .remote: RemoteView(goToSetup: goToSetup)
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
            Text(L10n.Remote.notConnectedTitle)
                .font(.title2.weight(.semibold))
            Text(L10n.Remote.notConnectedMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button(L10n.Remote.openSetup, action: goToSetup)
                .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if DEBUG
    #Preview {
        RemoteTabView(goToSetup: {})
    }
#endif
