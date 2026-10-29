enum DockVisibilityPolicy {
    /// Input is landscape-only, so its transition frame must not flash a dock
    /// that is about to disappear. Other tabs show the dock only in portrait.
    static func showsDock(
        isLandscape: Bool,
        selectedTab: AppTab
    ) -> Bool {
        !isLandscape && selectedTab != .input
    }
}
