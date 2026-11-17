import Foundation
@testable import StashCore

/// A temporary directory that is removed when the value is deallocated.
final class TempDirectory {
    let url: URL

    init() {
        // The real path, because that is what a bookmark hands back, and /var is a link to /private/var.
        let base = realpath(FileManager.default.temporaryDirectory.path, nil).map { pointer -> String in
            defer { free(pointer) }
            return String(cString: pointer)
        } ?? FileManager.default.temporaryDirectory.path
        url = URL(fileURLWithPath: base, isDirectory: true)
            .appendingPathComponent("stash-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        try? FileManager.default.removeItem(at: url)
    }

    /// Where the store under test keeps its list and its copies.
    var shelf: URL { url.appendingPathComponent("Shelf", isDirectory: true) }

    /// Creates a file that plays the part of one of the user's own files.
    @discardableResult
    func makeFile(_ name: String, content: String = "content") -> URL {
        let file = url.appendingPathComponent(name)
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(content.utf8).write(to: file)
        return file
    }

    @discardableResult
    func makeFolder(_ name: String) -> URL {
        let folder = url.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}

/// A clock the test moves by hand.
final class TestClock {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    func advance(days: Double) { now.addTimeInterval(days * 24 * 60 * 60) }
}

/// Everything about a file that must stay the same when Stash has been near it.
struct FileFingerprint: Equatable {
    let content: Data?
    let modified: Date?
    let inode: Int?
    let permissions: Int?

    init(_ url: URL) {
        content = try? Data(contentsOf: url)
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        modified = attributes?[.modificationDate] as? Date
        inode = (attributes?[.systemFileNumber] as? NSNumber)?.intValue
        permissions = (attributes?[.posixPermissions] as? NSNumber)?.intValue
    }
}
