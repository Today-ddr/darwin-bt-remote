import SwiftUI

extension FullKeyboardView {
    // Row definitions - each row sums to the MacBook Air's 14.5 units.

    /// MacBook function row: a wider Escape, then F1–F12 dividing the rest of the
    /// same 14.5-unit grid evenly. There is no Touch ID / power key, no Print
    /// Screen and no standalone forward delete, matching the MacBook Air keyboard
    /// this page models.
    ///
    /// 1.5 + twelve × 1.083333… = 14.5u.
    var row0: [FullKeyCap] {
        let functionKeyWidth = 13.0 / 12.0
        return [
            FullKeyCap(.text("Esc"), weight: 1.5, L10n.Keyboard.esc, .key(.escape)),
            FullKeyCap(.text("F1"), weight: functionKeyWidth, "F1", .key(.f1)),
            FullKeyCap(.text("F2"), weight: functionKeyWidth, "F2", .key(.f2)),
            FullKeyCap(.text("F3"), weight: functionKeyWidth, "F3", .key(.f3)),
            FullKeyCap(.text("F4"), weight: functionKeyWidth, "F4", .key(.f4)),
            FullKeyCap(.text("F5"), weight: functionKeyWidth, "F5", .key(.f5)),
            FullKeyCap(.text("F6"), weight: functionKeyWidth, "F6", .key(.f6)),
            FullKeyCap(.text("F7"), weight: functionKeyWidth, "F7", .key(.f7)),
            FullKeyCap(.text("F8"), weight: functionKeyWidth, "F8", .key(.f8)),
            FullKeyCap(.text("F9"), weight: functionKeyWidth, "F9", .key(.f9)),
            FullKeyCap(.text("F10"), weight: functionKeyWidth, "F10", .key(.f10)),
            FullKeyCap(.text("F11"), weight: functionKeyWidth, "F11", .key(.f11)),
            FullKeyCap(.text("F12"), weight: functionKeyWidth, "F12", .key(.f12))
        ]
    }

    /// Number row: ten 1u digits between the grave key and the two punctuation
    /// keys, closed by the MacBook's 1.5u Backspace.
    ///
    /// 1 + ten × 1 + 1 + 1 + 1.5 = 14.5u.
    var row1: [FullKeyCap] {
        [
            FullKeyCap(.dual(top: "~", bottom: "`"), weight: 1.0, "`", .key(.grave)),
            FullKeyCap(.dual(top: "!", bottom: "1"), weight: 1.0, "1", .key(.digit1)),
            FullKeyCap(.dual(top: "@", bottom: "2"), weight: 1.0, "2", .key(.digit2)),
            FullKeyCap(.dual(top: "#", bottom: "3"), weight: 1.0, "3", .key(.digit3)),
            FullKeyCap(.dual(top: "$", bottom: "4"), weight: 1.0, "4", .key(.digit4)),
            FullKeyCap(.dual(top: "%", bottom: "5"), weight: 1.0, "5", .key(.digit5)),
            FullKeyCap(.dual(top: "^", bottom: "6"), weight: 1.0, "6", .key(.digit6)),
            FullKeyCap(.dual(top: "&", bottom: "7"), weight: 1.0, "7", .key(.digit7)),
            FullKeyCap(.dual(top: "*", bottom: "8"), weight: 1.0, "8", .key(.digit8)),
            FullKeyCap(.dual(top: "(", bottom: "9"), weight: 1.0, "9", .key(.digit9)),
            FullKeyCap(.dual(top: ")", bottom: "0"), weight: 1.0, "0", .key(.digit0)),
            FullKeyCap(.dual(top: "_", bottom: "-"), weight: 1.0, "-", .key(.minus)),
            FullKeyCap(.dual(top: "+", bottom: "="), weight: 1.0, "=", .key(.equal)),
            FullKeyCap(.symbol("delete.left", ""), weight: 1.5, L10n.Keyboard.backspace, .key(.backspace))
        ]
    }

    /// Letter row: 1.5u Tab, the ten Q–P keys, then the three bracket and
    /// backslash keys at a plain 1u each.
    ///
    /// 1.5 + ten × 1 + 1 + 1 + 1 = 14.5u.
    var row2: [FullKeyCap] {
        [
            FullKeyCap(.symbol("arrow.right.to.line", "Tab"), weight: 1.5, L10n.Keyboard.tab, .key(.tab)),
            FullKeyCap(.letter("Q"), weight: 1.0, "Q", .key(.q)),
            FullKeyCap(.letter("W"), weight: 1.0, "W", .key(.w)),
            FullKeyCap(.letter("E"), weight: 1.0, "E", .key(.e)),
            FullKeyCap(.letter("R"), weight: 1.0, "R", .key(.r)),
            FullKeyCap(.letter("T"), weight: 1.0, "T", .key(.t)),
            FullKeyCap(.letter("Y"), weight: 1.0, "Y", .key(.y)),
            FullKeyCap(.letter("U"), weight: 1.0, "U", .key(.u)),
            FullKeyCap(.letter("I"), weight: 1.0, "I", .key(.i)),
            FullKeyCap(.letter("O"), weight: 1.0, "O", .key(.o)),
            FullKeyCap(.letter("P"), weight: 1.0, "P", .key(.p)),
            FullKeyCap(.dual(top: "{", bottom: "["), weight: 1.0, "[", .key(.leftBracket)),
            FullKeyCap(.dual(top: "}", bottom: "]"), weight: 1.0, "]", .key(.rightBracket)),
            FullKeyCap(.dual(top: "|", bottom: "\\"), weight: 1.0, "\\", .key(.backslash))
        ]
    }

    /// MacBook home row: Caps Lock and Return are both 1.75u, with the nine
    /// A–L keys and the two quote keys at 1u.
    ///
    /// 1.75 + nine × 1 + 1 + 1 + 1.75 = 14.5u.
    var row3: [FullKeyCap] {
        [
            FullKeyCap(.capsLock, weight: 1.75, L10n.Keyboard.capsLock, .capsLock),
            FullKeyCap(.letter("A"), weight: 1.0, "A", .key(.a)),
            FullKeyCap(.letter("S"), weight: 1.0, "S", .key(.s)),
            FullKeyCap(.letter("D"), weight: 1.0, "D", .key(.d)),
            FullKeyCap(.letter("F"), weight: 1.0, "F", .key(.f)),
            FullKeyCap(.letter("G"), weight: 1.0, "G", .key(.g)),
            FullKeyCap(.letter("H"), weight: 1.0, "H", .key(.h)),
            FullKeyCap(.letter("J"), weight: 1.0, "J", .key(.j)),
            FullKeyCap(.letter("K"), weight: 1.0, "K", .key(.k)),
            FullKeyCap(.letter("L"), weight: 1.0, "L", .key(.l)),
            FullKeyCap(.dual(top: ":", bottom: ";"), weight: 1.0, ";", .key(.semicolon)),
            FullKeyCap(.dual(top: "\"", bottom: "'"), weight: 1.0, "'", .key(.quote)),
            FullKeyCap(.symbol("return", "Enter"), weight: 1.75, L10n.Keyboard.enter, .key(.return))
        ]
    }

    /// MacBook shift row: a 2.25u Shift on each side of Z–M and the three
    /// comma/period/slash keys. The arrows are not on this row: Up and Down share
    /// one stacked cell on the bottom row, the way the MacBook arranges them.
    ///
    /// 2.25 + seven × 1 + 1 + 1 + 1 + 2.25 = 14.5u.
    var row4: [FullKeyCap] {
        [
            FullKeyCap(.modifier(name: "Shift", symbol: "⇧", mod: .leftShift), weight: 2.25, L10n.Keyboard.shift, .modifier(.leftShift)),
            FullKeyCap(.letter("Z"), weight: 1.0, "Z", .key(.z)),
            FullKeyCap(.letter("X"), weight: 1.0, "X", .key(.x)),
            FullKeyCap(.letter("C"), weight: 1.0, "C", .key(.c)),
            FullKeyCap(.letter("V"), weight: 1.0, "V", .key(.v)),
            FullKeyCap(.letter("B"), weight: 1.0, "B", .key(.b)),
            FullKeyCap(.letter("N"), weight: 1.0, "N", .key(.n)),
            FullKeyCap(.letter("M"), weight: 1.0, "M", .key(.m)),
            FullKeyCap(.dual(top: "<", bottom: ","), weight: 1.0, ",", .key(.comma)),
            FullKeyCap(.dual(top: ">", bottom: "."), weight: 1.0, ".", .key(.period)),
            FullKeyCap(.dual(top: "?", bottom: "/"), weight: 1.0, "/", .key(.slash)),
            FullKeyCap(.modifier(name: "Shift", symbol: "⇧", mod: .rightShift), weight: 2.25, L10n.Keyboard.shift, .modifier(.rightShift))
        ]
    }

    /// MacBook bottom row: Control, Option, Command, Space, Command, Option,
    /// then the four equally wide arrow columns. Left and Right are single caps;
    /// Up and Down share the column between them as two half-height caps. There is
    /// no Fn or Globe key on this page, by design.
    ///
    /// 1 + 1 + 1.25 + 6 + 1.25 + 1 + 1 + 1 + 1 = 14.5u.
    var row5: [FullKeyCap] {
        let upDown = FullKeyCap(
            .symbol("arrow.up", ""),
            weight: 1.0,
            L10n.Keyboard.up,
            .key(.upArrow),
            stackedBelow: FullKeyCap.Stacked(
                label: .symbol("arrow.down", ""),
                accessibility: L10n.Keyboard.down,
                action: .key(.downArrow)
            )
        )
        return [
            FullKeyCap(.modifier(name: "Ctrl", symbol: "⌃", mod: .leftCtrl), weight: 1.0, L10n.Keyboard.ctrl, .modifier(.leftCtrl)),
            FullKeyCap(.modifier(name: "Opt", symbol: "⌥", mod: .leftAlt), weight: 1.0, L10n.Keyboard.alt, .modifier(.leftAlt)),
            FullKeyCap(.modifier(name: "Cmd", symbol: "⌘", mod: .leftGUI), weight: 1.25, L10n.Keyboard.meta, .modifier(.leftGUI)),
            FullKeyCap(.text("Space"), weight: 6.0, L10n.Keyboard.space, .key(.space)),
            FullKeyCap(.modifier(name: "Cmd", symbol: "⌘", mod: .rightGUI), weight: 1.25, L10n.Keyboard.meta, .modifier(.rightGUI)),
            FullKeyCap(.modifier(name: "Opt", symbol: "⌥", mod: .rightAlt), weight: 1.0, L10n.Keyboard.alt, .modifier(.rightAlt)),
            FullKeyCap(.symbol("arrow.left", ""), weight: 1.0, L10n.Keyboard.left, .key(.leftArrow)),
            upDown,
            FullKeyCap(.symbol("arrow.right", ""), weight: 1.0, L10n.Keyboard.right, .key(.rightArrow))
        ]
    }
}

struct FullKeyCap {
    enum Label {
        case text(String)
        case letter(String)
        case dual(top: String, bottom: String)
        case symbol(String, String)
        case capsLock
        case modifier(name: String, symbol: String, mod: KeyboardModifiers)
    }

    enum Action {
        case key(Keycode)
        case modifier(KeyboardModifiers)
        case capsLock
    }

    /// The lower half of a vertically stacked cell. It carries its own label,
    /// accessibility text and action, so the cap below is as independent as the
    /// cap above it; only the grid cell and its width are shared.
    struct Stacked {
        let label: Label
        let accessibility: LocalizedStringKey
        let action: Action
    }

    let label: Label
    let weight: CGFloat
    let accessibility: LocalizedStringKey
    let action: Action
    /// When set, this cap is the top half of a vertical pair in one grid cell and
    /// `stackedBelow` is the bottom half. Nil for every ordinary cap.
    let stackedBelow: Stacked?

    init(
        _ label: Label,
        weight: CGFloat = 1.0,
        _ accessibility: LocalizedStringKey,
        _ action: Action,
        stackedBelow: Stacked? = nil
    ) {
        self.label = label
        self.weight = weight
        self.accessibility = accessibility
        self.action = action
        self.stackedBelow = stackedBelow
    }
}
