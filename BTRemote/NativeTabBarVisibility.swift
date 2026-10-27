import SwiftUI

#if os(iOS)
    extension View {
        @ViewBuilder
        func nativeTabBarHidden() -> some View {
            if #available(iOS 16.0, *) {
                toolbar(.hidden, for: .tabBar)
            } else {
                self
            }
        }
    }
#endif
