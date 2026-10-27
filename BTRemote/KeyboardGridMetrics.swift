import CoreGraphics

/// A shared horizontal grid for every full-keyboard row.
///
/// Gaps are taken out of each key's own logical slot rather than out of the row's
/// total before the unit width is calculated. Rows with different key counts then
/// keep the same horizontal pitch, which is what makes a key stay in the same
/// column as the row above it.
struct KeyboardGridMetrics: Equatable {
    static let totalUnits: CGFloat = 15

    let width: CGFloat
    let gap: CGFloat

    var unitWidth: CGFloat {
        max(0, width) / Self.totalUnits
    }

    func frame(
        startUnits: CGFloat,
        widthUnits: CGFloat,
        y: CGFloat = 0,
        height: CGFloat
    ) -> CGRect {
        CGRect(
            x: startUnits * unitWidth + gap / 2,
            y: y,
            width: max(0, widthUnits * unitWidth - gap),
            height: height
        )
    }
}
