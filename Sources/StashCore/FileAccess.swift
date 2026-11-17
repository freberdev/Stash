import Foundation

/// A file found through its bookmark.
public struct ResolvedFile {
    public var url: URL
    /// A replacement for a bookmark that the system reported as out of date.
    public var freshBookmark: Data?
    /// True when access to the file was opened and has to be closed again with `release`.
    public var holdsAccess: Bool

    public init(url: URL, freshBookmark: Data? = nil, holdsAccess: Bool = false) {
        self.url = url
        self.freshBookmark = freshBookmark
        self.holdsAccess = holdsAccess
    }
}

/// Remembers files across restarts without copying them.
public protocol FileAccess {
    /// A bookmark for a file the app has just been handed, for example by a drop.
    func bookmark(for url: URL) throws -> Data
    /// Finds the file a bookmark points at, also after it has been renamed or moved.
    /// Returns nil when the file is gone or its disk is not connected.
    func resolve(_ bookmark: Data) -> ResolvedFile?
    /// Gives back the access that `resolve` opened.
    func release(_ file: ResolvedFile)
}

/// Bookmarks that work inside the App Sandbox. They are made read-only: through such a
/// bookmark the system lets the app read the original, never change, move or delete it.
public struct BookmarkAccess: FileAccess {
    public init() {}

    public func bookmark(for url: URL) throws -> Data {
        do {
            return try scopedBookmark(for: url)
        } catch {
            // Outside the sandbox some volumes refuse a scoped bookmark. A plain one still follows the file.
            return try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        }
    }

    private func scopedBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    public func resolve(_ bookmark: Data) -> ResolvedFile? {
        // Never mount a network disk or show a dialog just to find out whether a file is there.
        let quiet: URL.BookmarkResolutionOptions = [.withoutUI, .withoutMounting]
        var isStale = false
        var isScoped = true
        var url = try? URL(
            resolvingBookmarkData: bookmark, options: quiet.union(.withSecurityScope),
            relativeTo: nil, bookmarkDataIsStale: &isStale)
        if url == nil {
            isScoped = false
            url = try? URL(
                resolvingBookmarkData: bookmark, options: quiet,
                relativeTo: nil, bookmarkDataIsStale: &isStale)
        }
        guard let url else { return nil }

        let holdsAccess = url.startAccessingSecurityScopedResource()
        // An out-of-date bookmark is replaced by one of the same kind or not at all: a plain
        // bookmark in place of a scoped one would lose access to the file at the next launch.
        var fresh: Data?
        if isStale {
            fresh = isScoped
                ? try? scopedBookmark(for: url)
                : try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        }
        return ResolvedFile(url: url, freshBookmark: fresh, holdsAccess: holdsAccess)
    }

    public func release(_ file: ResolvedFile) {
        if file.holdsAccess { file.url.stopAccessingSecurityScopedResource() }
    }
}
