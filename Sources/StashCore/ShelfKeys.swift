/// A key pressed together with modifiers.
///
/// `keyCode` is the hardware key, the same on every keyboard layout. `character` is what that
/// key types on the current layout, so that ⌘Z is the key marked Z whether the keyboard is
/// Swedish, French or German.
public struct KeyPress: Equatable, Sendable {
    public var keyCode: UInt16
    public var modifiers: KeyModifiers
    public var character: String?

    public init(keyCode: UInt16, modifiers: KeyModifiers, character: String? = nil) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.character = character
    }
}

/// What the shelf does in response to a key.
public enum ShelfCommand: Equatable, Sendable {
    case close
    case openSelected
    case removeSelected
    case copySelected
    case selectAll
    case undo
    case settings
}

/// The shelf's key table. Keys that are not listed, such as the arrows, go to the list as usual.
public enum ShelfKeys {
    private enum Key {
        static let returnKey: UInt16 = 36
        static let delete: UInt16 = 51
        static let escape: UInt16 = 53
        static let enter: UInt16 = 76
        static let forwardDelete: UInt16 = 117
    }

    /// The characters of the shortcut keys on a US keyboard, by key code. Used when the
    /// current layout gives no Latin character for a key.
    public static let usCharacters: [UInt16: String] = [
        0: "a", 6: "z", 8: "c", 12: "q", 13: "w", 43: ",",
    ]

    public static func command(for press: KeyPress) -> ShelfCommand? {
        // Keys without a character are matched by position.
        switch (press.keyCode, press.modifiers) {
        case (Key.escape, []):
            return .close
        case (Key.returnKey, []), (Key.enter, []):
            return .openSelected
        case (Key.delete, []), (Key.delete, .command), (Key.forwardDelete, []):
            return .removeSelected
        default:
            break
        }

        // Letters are matched by what the key types.
        switch (press.character?.lowercased(), press.modifiers) {
        case ("w", .command), ("q", .command):
            return .close
        case ("z", .command):
            return .undo
        case ("c", .command):
            return .copySelected
        case ("a", .command):
            return .selectAll
        case (",", .command):
            return .settings
        default:
            return nil
        }
    }
}
