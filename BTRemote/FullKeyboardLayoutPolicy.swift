import CoreGraphics

enum FullKeyboardPresentation: Equatable {
    case singleColumn
    case split(sidePanelWidth: CGFloat)
}

enum FullKeyboardLayoutPolicy {
    static let splitBreakpoint: CGFloat = 760
    static let sidePanelRatio: CGFloat = 0.27
    static let minimumSidePanelWidth: CGFloat = 180
    static let maximumSidePanelWidth: CGFloat = 300
    static let columnSpacing: CGFloat = 8
    static let minimumUnitWidth: CGFloat = 30
    static let keyGap: CGFloat = 4
    static let defaultKeyHorizontalMargin: CGFloat = 8

    /// In landscape the system safe area already accounts for the island and
    /// rounded corners. Removing the extra key margin there gives the 15 key
    /// columns the whole usable width; portrait and inset-free windows keep the
    /// breathing room around the keyboard.
    static func keyHorizontalMargin(
        isLandscape: Bool,
        safeAreaInset: CGFloat
    ) -> CGFloat {
        isLandscape && safeAreaInset > 0 ? 0 : defaultKeyHorizontalMargin
    }

    static func presentation(in size: CGSize) -> FullKeyboardPresentation {
        guard size.width > size.height, size.width >= splitBreakpoint else {
            return .singleColumn
        }

        let sidePanelWidth = min(
            maximumSidePanelWidth,
            max(minimumSidePanelWidth, size.width * sidePanelRatio)
        )
        let keyboardWidth = size.width - sidePanelWidth - columnSpacing
        let unitWidth = max(0, keyboardWidth) / KeyboardGridMetrics.totalUnits
        guard unitWidth >= minimumUnitWidth else {
            return .singleColumn
        }
        return .split(sidePanelWidth: sidePanelWidth)
    }
}
