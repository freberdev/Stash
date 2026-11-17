import Foundation

/// How long an item may stay on the shelf before it is cleared away by itself.
public enum Retention: Int, CaseIterable, Sendable {
    case never = 0
    case oneDay = 1
    case oneWeek = 7
    case oneMonth = 30

    /// The longest an item may stay, or nil when nothing is cleared automatically.
    public var interval: TimeInterval? {
        self == .never ? nil : TimeInterval(rawValue) * 24 * 60 * 60
    }
}
