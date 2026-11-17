import Foundation
import Observation
import UniformTypeIdentifiers

/// What came of putting things on the shelf.
public struct AddOutcome: Equatable, Sendable {
    public var added = 0
    /// Things that were on the shelf already. They are moved to the top instead of added twice.
    public var alreadyThere = 0
    public var failed = 0

    public init(added: Int = 0, alreadyThere: Int = 0, failed: Int = 0) {
        self.added = added
        self.alreadyThere = alreadyThere
        self.failed = failed
    }

    public static func + (left: AddOutcome, right: AddOutcome) -> AddOutcome {
        AddOutcome(
            added: left.added + right.added,
            alreadyThere: left.alreadyThere + right.alreadyThere,
            failed: left.failed + right.failed)
    }
}

/// The shelf: the items in the order they are shown, kept on disk between launches.
///
/// Files and folders are held as bookmarks. The store never writes to, moves or deletes
/// anything outside its own folder.
@MainActor @Observable
public final class ItemStore {
    /// Newest first.
    public private(set) var items: [StashItem] = []
    /// Items whose file cannot be found right now.
    public private(set) var missing: Set<UUID> = []
    /// True when the last attempt to write the list to disk failed.
    public private(set) var saveFailed = false
    /// How many removals can be taken back.
    public private(set) var undoDepth = 0

    public let directory: URL

    @ObservationIgnored private let access: any FileAccess
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var open: [UUID: ResolvedFile] = [:]
    @ObservationIgnored private var removed: [[Removal]] = []
    @ObservationIgnored private var couldNotReadList = false

    private struct Removal {
        let index: Int
        let item: StashItem
    }

    private struct Shelf: Codable {
        static let currentVersion = 1
        var version: Int
        var items: [StashItem]
    }

    public init(directory: URL, access: any FileAccess = BookmarkAccess(), now: @escaping () -> Date = Date.init) {
        self.directory = directory
        self.access = access
        self.now = now
    }

    /// The folder in Application Support where the shelf is kept.
    public static func defaultDirectory(named name: String = "Stash") -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(name, isDirectory: true)
    }

    public var canUndo: Bool { undoDepth > 0 }

    private var listFile: URL { directory.appendingPathComponent("items.json") }

    /// Where Stash keeps the files it holds itself.
    public var copiesDirectory: URL { directory.appendingPathComponent("Copies", isDirectory: true) }

    // MARK: Reading and writing

    public func load() {
        items = readList()
        refresh()
        removeOrphanedCopies()
    }

    private func readList() -> [StashItem] {
        guard let data = try? Data(contentsOf: listFile) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let shelf = try? decoder.decode(Shelf.self, from: data), shelf.version <= Shelf.currentVersion {
            return shelf.items
        }
        // A list that cannot be read is put aside rather than overwritten.
        couldNotReadList = true
        let aside = directory.appendingPathComponent("items.unreadable.json")
        try? FileManager.default.removeItem(at: aside)
        try? FileManager.default.moveItem(at: listFile, to: aside)
        return []
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(Shelf(version: Shelf.currentVersion, items: items))
            try data.write(to: listFile, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: listFile.path)
            saveFailed = false
        } catch {
            saveFailed = true
        }
    }

    // MARK: Adding

    /// Puts files and folders on the shelf as references. The files themselves are not touched.
    @discardableResult
    public func addFiles(_ urls: [URL]) -> AddOutcome {
        var outcome = AddOutcome()
        var top: [StashItem] = []

        // A dropped URL can be a file reference URL, which has an id where the path should be.
        for url in urls.map({ ($0 as NSURL).filePathURL ?? $0 }) {
            if top.contains(where: { open[$0.id]?.url.path == url.path }) {
                outcome.alreadyThere += 1
            } else if let index = items.firstIndex(where: { isReference($0, to: url) }) {
                var item = items.remove(at: index)
                if missing.contains(item.id), let bookmark = try? access.bookmark(for: url) {
                    // It was lost and has been handed over again: point at it afresh.
                    item.content = .reference(bookmark: bookmark, path: url.path)
                    missing.remove(item.id)
                    close(item.id)
                    open[item.id] = ResolvedFile(url: url)
                }
                top.append(item)
                outcome.alreadyThere += 1
            } else if let bookmark = try? access.bookmark(for: url) {
                let item = StashItem(
                    kind: Self.isFolder(url) ? .folder : .file, name: url.lastPathComponent,
                    content: .reference(bookmark: bookmark, path: url.path), added: now())
                // The app keeps the access it was given with the drop for as long as it runs.
                open[item.id] = ResolvedFile(url: url)
                top.append(item)
                outcome.added += 1
            } else {
                outcome.failed += 1
            }
        }

        if !top.isEmpty {
            items.insert(contentsOf: top, at: 0)
            save()
        }
        return outcome
    }

    @discardableResult
    public func addLink(_ url: URL, title: String? = nil) -> AddOutcome {
        if moveToTop(where: { $0.content == .link(url: url) }) { return AddOutcome(alreadyThere: 1) }
        let title = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = title.flatMap { $0.isEmpty ? nil : $0 } ?? url.host ?? url.absoluteString
        return insert(StashItem(kind: .link, name: name, content: .link(url: url), added: now()))
    }

    @discardableResult
    public func addText(_ text: String) -> AddOutcome {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return AddOutcome(failed: 1) }
        if moveToTop(where: { $0.content == .text(string: text) }) { return AddOutcome(alreadyThere: 1) }
        return insert(StashItem(
            kind: .text, name: PathDisplay.title(forText: text), content: .text(string: text), added: now()))
    }

    /// Keeps image data that was dragged in without a file of its own.
    @discardableResult
    public func addImage(_ data: Data, fileName: String) -> AddOutcome {
        do {
            let file = try makeCopyDirectory().appendingPathComponent(fileName)
            try data.write(to: file, options: .atomic)
            return addCopy(at: file)
        } catch {
            return AddOutcome(failed: 1)
        }
    }

    /// A new, empty folder inside the Copies folder, for a file that is about to be delivered.
    public func makeCopyDirectory() throws -> URL {
        let folder = copiesDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return folder
    }

    /// Puts a file that already lies in a folder from `makeCopyDirectory` on the shelf.
    @discardableResult
    public func addCopy(at file: URL) -> AddOutcome {
        let folder = file.deletingLastPathComponent().lastPathComponent
        guard UUID(uuidString: folder) != nil, FileManager.default.fileExists(atPath: file.path) else {
            return AddOutcome(failed: 1)
        }
        let kind: StashItem.Kind
        if Self.isFolder(file) {
            kind = .folder
        } else if UTType(filenameExtension: file.pathExtension)?.conforms(to: .image) == true {
            kind = .image
        } else {
            kind = .file
        }
        return insert(StashItem(
            kind: kind, name: file.lastPathComponent,
            content: .copy(path: folder + "/" + file.lastPathComponent), added: now()))
    }

    private func insert(_ item: StashItem) -> AddOutcome {
        items.insert(item, at: 0)
        save()
        return AddOutcome(added: 1)
    }

    private func moveToTop(where matches: (StashItem) -> Bool) -> Bool {
        guard let index = items.firstIndex(where: matches) else { return false }
        if index > 0 {
            items.insert(items.remove(at: index), at: 0)
            save()
        }
        return true
    }

    private func isReference(_ item: StashItem, to url: URL) -> Bool {
        guard case .reference(_, let path) = item.content else { return false }
        return (open[item.id]?.url.path ?? path) == url.path
    }

    private static func isFolder(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        return values?.isDirectory == true && values?.isPackage != true
    }

    // MARK: Removing

    /// Takes items off the shelf. Originals are left exactly as they are.
    @discardableResult
    public func remove(_ ids: Set<UUID>) -> Int {
        let batch = items.enumerated()
            .filter { ids.contains($0.element.id) }
            .map { Removal(index: $0.offset, item: $0.element) }
        guard !batch.isEmpty else { return 0 }

        for removal in batch { close(removal.item.id) }
        items.removeAll { ids.contains($0.id) }
        missing.subtract(ids)
        removed.append(batch)
        undoDepth = removed.count
        save()
        return batch.count
    }

    @discardableResult
    public func clear() -> Int {
        remove(Set(items.map(\.id)))
    }

    /// Puts back what was removed last, where it was. Returns how many items came back.
    @discardableResult
    public func undo() -> Int {
        guard let batch = removed.popLast() else { return 0 }
        for removal in batch {
            items.insert(removal.item, at: min(removal.index, items.count))
        }
        undoDepth = removed.count
        refresh()
        save()
        return batch.count
    }

    /// Gives up the chance to undo, and deletes the copies that were only kept for that.
    public func forgetRemoved() {
        for item in removed.joined().map(\.item) { deleteCopy(of: item) }
        removed = []
        undoDepth = 0
    }

    /// Removes items that have been on the shelf longer than the chosen time. This is not undoable.
    @discardableResult
    public func removeExpired(_ retention: Retention) -> Int {
        guard let interval = retention.interval else { return 0 }
        let cutoff = now().addingTimeInterval(-interval)
        let expired = items.filter { $0.added <= cutoff }
        guard !expired.isEmpty else { return 0 }

        let ids = Set(expired.map(\.id))
        for item in expired {
            close(item.id)
            deleteCopy(of: item)
        }
        items.removeAll { ids.contains($0.id) }
        missing.subtract(ids)
        save()
        return expired.count
    }

    private func close(_ id: UUID) {
        if let file = open.removeValue(forKey: id) { access.release(file) }
    }

    private func deleteCopy(of item: StashItem) {
        guard case .copy(let path) = item.content else { return }
        let file = copiesDirectory.appendingPathComponent(path)
        try? FileManager.default.removeItem(at: file)
        // The folder goes too, once it is empty.
        let folder = file.deletingLastPathComponent()
        if (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.isEmpty == true {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    /// Deletes files in the Copies folder that no item refers to, left behind by a crash for example.
    private func removeOrphanedCopies() {
        // If the list could not be read, every copy would look orphaned. Leave them be.
        guard !couldNotReadList else { return }
        let fm = FileManager.default
        var known: Set<String> = []
        for item in items {
            if case .copy(let path) = item.content { known.insert(path) }
        }
        for folder in (try? fm.contentsOfDirectory(atPath: copiesDirectory.path)) ?? [] {
            let folderURL = copiesDirectory.appendingPathComponent(folder, isDirectory: true)
            let names = (try? fm.contentsOfDirectory(atPath: folderURL.path)) ?? []
            var kept = 0
            for name in names {
                if known.contains(folder + "/" + name) {
                    kept += 1
                } else {
                    try? fm.removeItem(at: folderURL.appendingPathComponent(name))
                }
            }
            if kept == 0 { try? fm.removeItem(at: folderURL) }
        }
    }

    // MARK: Using

    /// The file behind an item, or nil for links and text and for files that cannot be found.
    public func fileURL(for item: StashItem) -> URL? {
        guard !missing.contains(item.id) else { return nil }
        switch item.content {
        case .reference: return open[item.id]?.url
        case .copy(let path): return copiesDirectory.appendingPathComponent(path)
        case .link, .text: return nil
        }
    }

    /// Notes that items were just dragged out, opened or copied.
    public func markUsed(_ ids: Set<UUID>) {
        var changed = false
        let time = now()
        for index in items.indices where ids.contains(items[index].id) {
            items[index].lastUsed = time
            changed = true
        }
        if changed { save() }
    }

    // MARK: Keeping up with the files

    /// Looks for every file again. Follows files that were renamed or moved, and marks those
    /// that are gone, in the Trash or on a disk that is not connected.
    public func refresh() {
        var nowMissing: Set<UUID> = []
        var changed = false

        for index in items.indices {
            let item = items[index]
            switch item.content {
            case .reference(let bookmark, let path):
                if let file = open[item.id], Self.isPresent(file.url) { continue }
                // Not where it was. The bookmark knows if it has only been renamed or moved.
                close(item.id)
                guard let file = access.resolve(bookmark) else {
                    nowMissing.insert(item.id)
                    continue
                }
                guard Self.isPresent(file.url) else {
                    access.release(file)
                    nowMissing.insert(item.id)
                    continue
                }
                open[item.id] = file
                if file.url.path != path || file.freshBookmark != nil {
                    items[index].content = .reference(bookmark: file.freshBookmark ?? bookmark, path: file.url.path)
                    items[index].name = file.url.lastPathComponent
                    changed = true
                }
            case .copy(let path):
                if !FileManager.default.fileExists(atPath: copiesDirectory.appendingPathComponent(path).path) {
                    nowMissing.insert(item.id)
                }
            case .link, .text:
                break
            }
        }

        if nowMissing != missing { missing = nowMissing }
        if changed { save() }
    }

    private static func isPresent(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path) && !PathDisplay.isInTrash(url.path)
    }
}
