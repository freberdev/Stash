import Carbon.HIToolbox

/// Turns a hardware key code into what is printed on the key in the current keyboard layout.
@MainActor
enum KeyNames {
    private static let special: [UInt32: String] = [
        UInt32(kVK_Space): "Space", UInt32(kVK_Return): "↩", UInt32(kVK_ANSI_KeypadEnter): "⌤",
        UInt32(kVK_Tab): "⇥", UInt32(kVK_Delete): "⌫", UInt32(kVK_ForwardDelete): "⌦",
        UInt32(kVK_Escape): "⎋", UInt32(kVK_LeftArrow): "←", UInt32(kVK_RightArrow): "→",
        UInt32(kVK_UpArrow): "↑", UInt32(kVK_DownArrow): "↓", UInt32(kVK_Home): "↖",
        UInt32(kVK_End): "↘", UInt32(kVK_PageUp): "⇞", UInt32(kVK_PageDown): "⇟",
        UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3", UInt32(kVK_F4): "F4",
        UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6", UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8",
        UInt32(kVK_F9): "F9", UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
    ]

    static func name(for keyCode: UInt32) -> String {
        if let name = special[keyCode] { return name }
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return "?" }
        let layout = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data

        var deadKeys: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = layout.withUnsafeBytes { bytes in
            UCKeyTranslate(
                bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress,
                UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, characters.count, &length, &characters)
        }
        guard status == noErr, length > 0 else { return "?" }
        return String(utf16CodeUnits: characters, count: length).uppercased()
    }
}
