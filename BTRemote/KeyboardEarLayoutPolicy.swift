import CoreGraphics

/// Positions the landscape status badges inside the two horizontal safe-area
/// ears. The frame is measured on the unmodified screen, before the keyboard
/// adds its own safe-area padding, so the ear and key coordinates cannot drift
/// apart when the keyboard extends under the rounded corners.
enum KeyboardEarLayoutPolicy {
    static let badgeWidth: CGFloat = 38
    static let minimumEarWidth: CGFloat = 42
    static let minimumEdgePadding: CGFloat = 3

    static func showsBadge(in size: CGSize, earWidth: CGFloat) -> Bool {
        size.width > size.height && earWidth >= minimumEarWidth
    }

    static func badgePadding(for earWidth: CGFloat) -> CGFloat {
        max(minimumEdgePadding, (earWidth - badgeWidth) / 2)
    }
}
