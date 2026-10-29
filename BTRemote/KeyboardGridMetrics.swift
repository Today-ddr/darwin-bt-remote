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

/// Vertical geometry of a stacked grid cell, such as the bottom row's Up/Down pair.
///
/// The cell is split into two equal touch bands that meet at the middle, so a finger
/// anywhere in the cell lands on one of the two arrows and no dead strip sits between
/// them. The caps keep the rows' visual gap by pulling each one back from that shared
/// edge by half the gap: the gap is drawn, but it is not untouchable. Each band is
/// still its own touch layer, so the halves stay independently pressed and released.
struct StackedKeyCellGeometry: Equatable {
    let cellHeight: CGFloat
    let gap: CGFloat

    /// One band's height. The two bands together are exactly `cellHeight`.
    var touchHeight: CGFloat {
        max(0, cellHeight) / 2
    }

    /// How far each visible cap is pulled back from the shared middle edge.
    var capInset: CGFloat {
        min(max(0, gap) / 2, touchHeight)
    }

    /// The top cap's touch band, in the cell's coordinates.
    func topTouchFrame(width: CGFloat) -> CGRect {
        CGRect(x: 0, y: 0, width: max(0, width), height: touchHeight)
    }

    /// The bottom cap's touch band, starting where the top band ends.
    func bottomTouchFrame(width: CGFloat) -> CGRect {
        CGRect(x: 0, y: touchHeight, width: max(0, width), height: touchHeight)
    }

    /// The visible top cap: its touch band less the half gap above the middle.
    func topCapFrame(width: CGFloat) -> CGRect {
        CGRect(x: 0, y: 0, width: max(0, width), height: touchHeight - capInset)
    }

    /// The visible bottom cap, pulled down from the middle by the half gap.
    func bottomCapFrame(width: CGFloat) -> CGRect {
        CGRect(
            x: 0,
            y: touchHeight + capInset,
            width: max(0, width),
            height: touchHeight - capInset
        )
    }
}
