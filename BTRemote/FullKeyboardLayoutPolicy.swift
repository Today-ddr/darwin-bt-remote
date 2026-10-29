import CoreGraphics

enum FullKeyboardLayoutPolicy {
    static let keyGap: CGFloat = 4
    static let defaultKeyHorizontalMargin: CGFloat = 8

    /// In landscape the system safe area already accounts for the island and
    /// rounded corners. Removing the extra key margin there gives the 14.5-unit
    /// grid the whole usable width; portrait and inset-free windows keep the
    /// breathing room around the keyboard.
    static func keyHorizontalMargin(
        isLandscape: Bool,
        safeAreaInset: CGFloat
    ) -> CGFloat {
        isLandscape && safeAreaInset > 0 ? 0 : defaultKeyHorizontalMargin
    }
}
