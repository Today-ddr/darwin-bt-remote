import CoreGraphics

/// Positions the landscape status badge inside the horizontal safe-area ear.
/// The badge is hosted by the root content view, outside the keyboard's safe
/// area, so its coordinate origin is the screen rather than the leading key.
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

    static func badgeLeadingOffset(
        for earWidth: CGFloat,
        coordinateOriginX: CGFloat
    ) -> CGFloat {
        badgePadding(for: earWidth) - coordinateOriginX
    }
}
