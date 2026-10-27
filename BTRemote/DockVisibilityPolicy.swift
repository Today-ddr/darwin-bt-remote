enum DockVisibilityPolicy {
    static func showsDock(
        hidesDockInLandscape: Bool,
        isLandscape: Bool,
        selectedTab: AppTab,
        remoteMode: RemoteMode,
        keyboardPageRawValue: Int
    ) -> Bool {
        guard hidesDockInLandscape else { return true }
        let isLandscapeCombo =
            isLandscape
                && selectedTab == .remote
                && remoteMode == .keyboard
                && keyboardPageRawValue == KeyboardPage.fullKeyboard.rawValue
        return !isLandscapeCombo
    }
}
