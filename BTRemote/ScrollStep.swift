import CoreGraphics

/// The step the right-side Up and Down buttons send.
///
/// One tap is one small relative wheel report. The value never collapses to zero,
/// so a tap always moves the host, and the natural / inverted preference is applied
/// at the same place that decides the direction.
enum ScrollStep {
    static func amount(scrollSensitivity: Double) -> Int8 {
        max(1, HIDInput.clamp(CGFloat(3 * scrollSensitivity)))
    }

    /// `direction` is +1 for Up and -1 for Down.
    static func wheel(
        direction: Int8,
        scrollSensitivity: Double,
        invertScroll: Bool
    ) -> Int8 {
        let amount = amount(scrollSensitivity: scrollSensitivity)
        let base = direction < 0 ? -amount : amount
        return invertScroll ? -base : base
    }
}
