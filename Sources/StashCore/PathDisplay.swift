import Foundation

/// Paths as they are shown to the user.
public enum PathDisplay {
    /// The user's real home folder. Inside the App Sandbox `NSHomeDirectory()` is the app's
    /// container, which is not where the user's files are.
    public static var home: String {
        if let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir {
            return String(cString: directory)
        }
        return NSHomeDirectory()
    }

    /// The folder a file is in, with the home folder written as "~".
    public static func folder(ofPath path: String, home: String = PathDisplay.home) -> String {
        abbreviate((path as NSString).deletingLastPathComponent, home: home)
    }

    /// A path with the home folder written as "~".
    public static func abbreviate(_ path: String, home: String = PathDisplay.home) -> String {
        let home = home.hasSuffix("/") ? String(home.dropLast()) : home
        guard !home.isEmpty else { return path }
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    /// True for a file that lies in a Trash folder, on the startup disk or on another volume.
    public static func isInTrash(_ path: String) -> Bool {
        let components = (path as NSString).pathComponents
        return components.contains(".Trash") || components.contains(".Trashes")
    }

    /// True for a file in a place the system or another app cleans up by itself: a temporary
    /// folder or a cache. A reference to such a file would soon point at nothing.
    public static func isTemporary(_ path: String) -> Bool {
        let roots = ["/private/var/folders/", "/var/folders/", "/private/tmp/", "/tmp/"]
        if roots.contains(where: path.hasPrefix) { return true }
        let folders = (path as NSString).deletingLastPathComponent + "/"
        return ["/TemporaryItems/", "/Library/Caches/", "/tmp/"].contains(where: folders.contains)
    }

    /// A one-line name for a piece of text: its first line with something on it, cut to a sensible length.
    public static func title(forText text: String, limit: Int = 80) -> String {
        let line = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        return line.count > limit ? String(line.prefix(limit)) + "…" : line
    }

    /// A link without its scheme and without a trailing slash, as it is shown under the title.
    public static func compact(_ url: URL) -> String {
        var text = url.absoluteString
        for prefix in ["https://", "http://"] where text.hasPrefix(prefix) {
            text.removeFirst(prefix.count)
        }
        if text.hasSuffix("/") { text.removeLast() }
        return text
    }
}
