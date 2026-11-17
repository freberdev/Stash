import Foundation
import Testing
@testable import StashCore

@Suite struct ShelfKeysTests {
    func command(_ keyCode: UInt16, _ modifiers: KeyModifiers = [], _ character: String? = nil) -> ShelfCommand? {
        ShelfKeys.command(for: KeyPress(keyCode: keyCode, modifiers: modifiers, character: character))
    }

    @Test func escapeCloses() {
        #expect(command(53) == .close)
        #expect(command(53, .shift) == nil)
    }

    @Test func returnOpens() {
        #expect(command(36) == .openSelected)
        #expect(command(76) == .openSelected)
    }

    @Test func deleteRemoves() {
        #expect(command(51) == .removeSelected)
        #expect(command(51, .command) == .removeSelected)
        #expect(command(117) == .removeSelected)
        #expect(command(51, .option) == nil)
    }

    @Test func lettersFollowWhatTheKeyTypes() {
        // On a French keyboard the key in the position of Q types A.
        #expect(command(12, .command, "a") == .selectAll)
        #expect(command(0, .command, "q") == .close)
        #expect(command(6, .command, "Z") == .undo)
        #expect(command(8, .command, "c") == .copySelected)
        #expect(command(13, .command, "w") == .close)
        #expect(command(43, .command, ",") == .settings)
    }

    @Test func otherKeysAreLeftToTheList() {
        #expect(command(125) == nil)
        #expect(command(126) == nil)
        #expect(command(0, [], "a") == nil)
        #expect(command(8, [.command, .shift], "c") == nil)
        #expect(command(6, .command, nil) == nil)
    }
}
