import Foundation

/// The language the app is shown in.
public enum AppLanguage: String, CaseIterable, Sendable {
    /// Whatever the Mac is set to: Swedish if that comes first of the two, otherwise English.
    case system
    case swedish = "sv"
    case english = "en"

    private static let key = "AppleLanguages"

    /// The language chosen for this app, read from where macOS itself keeps a per-app language.
    /// A choice made under System Settings > Language & Region > Applications shows up here too.
    public static func chosen(in defaults: UserDefaults = .standard, domain: String) -> AppLanguage {
        let stored = defaults.persistentDomain(forName: domain)?[key] as? [String]
        guard let first = stored?.first else { return .system }
        // "sv-SE" and "sv" are both Swedish.
        let code = first.split(separator: "-").first.map(String.init) ?? first
        return AppLanguage(rawValue: code) ?? .system
    }

    /// Stores the choice. macOS reads it when the app starts, so it takes effect at the next launch.
    public func store(in defaults: UserDefaults = .standard) {
        switch self {
        case .system: defaults.removeObject(forKey: Self.key)
        case .swedish, .english: defaults.set([rawValue], forKey: Self.key)
        }
    }
}
