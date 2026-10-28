enum DockVisibilityPolicy {
    static func showsDock(
        hidesDockInLandscape: Bool,
        isLandscape: Bool,
        selectedTab: AppTab,
        inputPageRawValue: Int
    ) -> Bool {
        guard hidesDockInLandscape else { return true }
        let isLandscapeCombo =
            isLandscape
                && selectedTab == .input
                && inputPageRawValue == InputPage.keyboard.rawValue
        return !isLandscapeCombo
    }
}
