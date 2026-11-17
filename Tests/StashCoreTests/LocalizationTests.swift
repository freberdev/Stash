import Foundation
import Testing

/// Keeps the two languages, and the keys the app asks for, in step with each other.
@Suite struct LocalizationTests {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func strings(_ language: String) throws -> [String: String] {
        let url = root.appendingPathComponent("Resources/\(language).lproj/Localizable.strings")
        let text = try String(contentsOf: url, encoding: .utf8)
        var result: [String: String] = [:]
        for match in text.matches(of: /(?m)^"([^"]+)"\s*=\s*"((?:[^"\\]|\\.)*)";\s*$/) {
            result[String(match.1)] = String(match.2)
        }
        return result
    }

    static func keysUsedInSources() throws -> Set<String> {
        let directory = root.appendingPathComponent("Sources/Stash")
        var keys: Set<String> = []
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        where file.pathExtension == "swift" {
            let source = try String(contentsOf: file, encoding: .utf8)
            for match in source.matches(of: /\bL\("([A-Za-z0-9.]+)"/) {
                keys.insert(String(match.1))
            }
            // Counted phrases name their singular and plural keys.
            for match in source.matches(of: /\b(?:one|many): "([A-Za-z0-9.]+)"/) {
                keys.insert(String(match.1))
            }
        }
        return keys
    }

    static func placeholders(in value: String) -> [String] {
        value.matches(of: /%(?:ld|@|d)/).map { String($0.0) }
    }

    @Test func bothLanguagesHaveTheSameKeys() throws {
        let english = try Self.strings("en"), swedish = try Self.strings("sv")
        #expect(!english.isEmpty)
        #expect(Set(english.keys) == Set(swedish.keys))
    }

    @Test func noValueIsEmpty() throws {
        for language in ["en", "sv"] {
            for (key, value) in try Self.strings(language) {
                #expect(!value.isEmpty, "\(language): \(key)")
            }
        }
    }

    @Test func placeholdersMatchBetweenLanguages() throws {
        let english = try Self.strings("en"), swedish = try Self.strings("sv")
        for (key, value) in english {
            #expect(Self.placeholders(in: value) == Self.placeholders(in: swedish[key] ?? ""), "\(key)")
        }
    }

    @Test func everyKeyTheAppUsesExists() throws {
        let english = try Self.strings("en")
        let used = try Self.keysUsedInSources()
        #expect(!used.isEmpty)
        #expect(used.subtracting(english.keys).isEmpty, "missing: \(used.subtracting(english.keys).sorted())")
    }

    @Test func noKeyIsLeftUnused() throws {
        let english = try Self.strings("en")
        let used = try Self.keysUsedInSources()
        #expect(Set(english.keys).subtracting(used).isEmpty, "unused: \(Set(english.keys).subtracting(used).sorted())")
    }
}
