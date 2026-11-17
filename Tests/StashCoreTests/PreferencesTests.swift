import Foundation
import Testing
@testable import StashCore

@Suite struct PreferencesTests {
    let suite = "stash-tests-\(UUID().uuidString)"

    func makePreferences() -> Preferences {
        Preferences(defaults: UserDefaults(suiteName: suite)!)
    }

    @Test func defaults() {
        let preferences = makePreferences()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        #expect(preferences.shortcut == .default)
        #expect(preferences.retention == .never)
        #expect(!preferences.didAutoEnableLoginItem)
        #expect(!preferences.hasShownWelcome)
    }

    @Test func valuesAreKept() {
        let preferences = makePreferences()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        preferences.shortcut = Shortcut(keyCode: 9, modifiers: [.command, .shift])
        preferences.retention = .oneWeek
        preferences.didAutoEnableLoginItem = true
        preferences.hasShownWelcome = true

        let again = makePreferences()
        #expect(again.shortcut == Shortcut(keyCode: 9, modifiers: [.command, .shift]))
        #expect(again.retention == .oneWeek)
        #expect(again.didAutoEnableLoginItem)
        #expect(again.hasShownWelcome)
    }

    @Test func anUnusableShortcutOrRetentionFallsBack() {
        let defaults = UserDefaults(suiteName: suite)!
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        defaults.set(try? JSONEncoder().encode(Shortcut(keyCode: 1, modifiers: .option)), forKey: "shortcut")
        defaults.set(5, forKey: "retentionDays")
        #expect(Preferences(defaults: defaults).shortcut == .default)
        #expect(Preferences(defaults: defaults).retention == .never)
    }
}
