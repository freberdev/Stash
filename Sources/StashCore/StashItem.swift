import Foundation

/// One thing on the shelf.
public struct StashItem: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case file, folder, link, text, image
    }

    /// Where the item's content lives.
    public enum Content: Codable, Equatable, Sendable {
        /// A file or folder somewhere else on the Mac. Stash keeps a bookmark to it, never the file.
        /// `path` is where it was last seen, and is what is shown when it can no longer be found.
        case reference(bookmark: Data, path: String)
        /// A file Stash keeps itself, because what was dragged in had no file of its own.
        /// `path` is relative to the store's Copies folder.
        case copy(path: String)
        case link(url: URL)
        case text(string: String)
    }

    public let id: UUID
    public var kind: Kind
    public var name: String
    public var content: Content
    public var added: Date
    public var lastUsed: Date?

    public init(
        id: UUID = UUID(), kind: Kind, name: String, content: Content, added: Date, lastUsed: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.content = content
        self.added = added
        self.lastUsed = lastUsed
    }

    /// True when the item points at an original that lives outside Stash.
    public var isReference: Bool {
        if case .reference = content { return true }
        return false
    }

    /// True when Stash holds the only copy of the item's file.
    public var isCopy: Bool {
        if case .copy = content { return true }
        return false
    }
}
