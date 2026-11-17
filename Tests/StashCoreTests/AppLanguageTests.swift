import Foundation
import Testing
@testable import StashCore

@Suite struct AppLanguageTests {
    let suite = "stash-tests-\(UUID().uuidString)"

    func chosen() -> AppLanguage {
        AppLanguage.chosen(in: UserDefaults(suiteName: suite)!, domain: suite)
    }

    @Test func nothingChosenMeansTheSystemLanguage() {
        #expect(chosen() == .system)
    }

    @Test func aChoiceIsStoredWhereMacOSLooksForIt() {
        let defaults = UserDefaults(suiteName: suite)!
        defer { UserDefaults().removePersistentDomain(forName: suite) }

        AppLanguage.swedish.store(in: defaults)
        #expect(defaults.persistentDomain(forName: suite)?["AppleLanguages"] as? [String] == ["sv"])
        #expect(chosen() == .swedish)

        AppLanguage.english.store(in: defaults)
        #expect(chosen() == .english)

        AppLanguage.system.store(in: defaults)
        #expect(defaults.persistentDomain(forName: suite)?["AppleLanguages"] == nil)
        #expect(chosen() == .system)
    }

    @Test func aRegionOnTheLanguageIsIgnored() {
        let defaults = UserDefaults(suiteName: suite)!
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        defaults.set(["sv-SE", "en-SE"], forKey: "AppleLanguages")
        #expect(chosen() == .swedish)
        defaults.set(["en-GB"], forKey: "AppleLanguages")
        #expect(chosen() == .english)
    }

    @Test func aLanguageTheAppDoesNotHaveMeansTheSystemLanguage() {
        let defaults = UserDefaults(suiteName: suite)!
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        defaults.set(["de"], forKey: "AppleLanguages")
        #expect(chosen() == .system)
    }
}
