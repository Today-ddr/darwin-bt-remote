import Foundation

/// Reference counts held keys by usage.
///
/// Two fingers on the same cap are still one logical key press, and the key is
/// released only when the last finger leaves. The keyboard view applies every
/// transition synchronously on the main actor, in the order the touch callbacks
/// arrive, so an older release can never overwrite a newer press.
struct KeyPressTracker: Equatable {
    private(set) var counts: [Keycode: Int] = [:]

    var heldKeys: Set<Keycode> {
        Set(counts.keys)
    }

    var isEmpty: Bool {
        counts.isEmpty
    }

    /// Returns true when this is the first finger on the key.
    @discardableResult
    mutating func press(_ key: Keycode) -> Bool {
        let count = (counts[key] ?? 0) + 1
        counts[key] = count
        return count == 1
    }

    /// Returns true when the last finger has left the key.
    @discardableResult
    mutating func release(_ key: Keycode) -> Bool {
        guard let count = counts[key] else { return false }
        guard count > 1 else {
            counts.removeValue(forKey: key)
            return true
        }
        counts[key] = count - 1
        return false
    }

    mutating func removeAll() {
        counts.removeAll()
    }
}
