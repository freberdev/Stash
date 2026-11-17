import Foundation
import Testing
@testable import StashCore

@Suite struct ShortcutTests {
    @Test func defaultIsControlOptionS() {
        #expect(Shortcut.default.keyCode == 1)
        #expect(Shortcut.default.modifiers == [.control, .option])
        #expect(Shortcut.default.isValid)
        #expect(Shortcut.default.modifierSymbols == "⌃⌥")
        #expect(Shortcut.default.carbonModifiers == 0x1800)
    }

    @Test func aShortcutNeedsCommandOrControl() {
        #expect(!Shortcut(keyCode: 1, modifiers: .option).isValid)
        #expect(!Shortcut(keyCode: 1, modifiers: [.option, .shift]).isValid)
        #expect(!Shortcut(keyCode: 1, modifiers: []).isValid)
        #expect(Shortcut(keyCode: 1, modifiers: .command).isValid)
        #expect(Shortcut(keyCode: 1, modifiers: [.control, .shift]).isValid)
    }

    @Test func allFourModifiers() {
        let all = Shortcut(keyCode: 0, modifiers: [.command, .shift, .option, .control])
        #expect(all.carbonModifiers == 0x1B00)
        #expect(all.modifierSymbols == "⌃⌥⇧⌘")
    }
}
