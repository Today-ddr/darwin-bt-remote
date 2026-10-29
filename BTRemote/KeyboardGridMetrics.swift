import CoreGraphics

/// A shared horizontal grid for every full-keyboard row.
///
/// The grid is the MacBook Air's 14.5-unit width: Escape is 1.5u and the twelve
/// function keys split the remaining 13u, while the rows below keep Apple's
/// 1u letter keys with 1.5u Tab/Backspace and 1.75u Caps/Return.
///
/// Gaps are taken out of each key's own logical slot rather than out of the row's
/// total before the unit width is calculated. Rows with different key counts then
/// keep the same horizontal pitch, which is what makes a key stay in the same
/// column as the row above it.
struct KeyboardGridMetrics: Equatable {
    static let totalUnits: CGFloat = 14.5

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
