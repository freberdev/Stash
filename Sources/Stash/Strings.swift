import Foundation

/// Looks up a user-facing string by key in the app's Localizable.strings.
func L(_ key: String) -> String {
    NSLocalizedString(key, bundle: .main, comment: "")
}

/// Looks up a format string by key and fills in the arguments.
func L(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: L(key), locale: .current, arguments: arguments)
}

/// Picks the singular or plural form of a counted phrase. The plural form takes the number.
func L(count: Int, one: String, many: String) -> String {
    count == 1 ? L(one) : L(many, count)
}
