import AppKit
import QuickLookThumbnailing
import StashCore
import UniformTypeIdentifiers

/// The words shown for an item: its name, what and where it is, and whether it is a
/// reference to an original or a copy that Stash keeps.
struct ItemDescription {
    let title: String
    let subtitle: String
    let toolTip: String
    let isMissing: Bool

    init(_ item: StashItem, isMissing: Bool) {
        self.isMissing = isMissing
        title = item.name

        switch item.content {
        case .reference(_, let path):
            let shownPath = PathDisplay.abbreviate(path)
            if isMissing {
                subtitle = L("item.missing")
                toolTip = L("item.tip.missing", shownPath)
            } else {
                subtitle = Self.kind(of: item, path: path) + " · " + PathDisplay.folder(ofPath: path)
                toolTip = L("item.tip.reference", shownPath)
            }
        case .copy:
            subtitle = isMissing
                ? L("item.missing")
                : Self.kind(of: item, path: item.name) + " · " + L("item.copy")
            toolTip = L("item.tip.copy")
        case .link(let url):
            subtitle = PathDisplay.compact(url)
            toolTip = url.absoluteString
        case .text(let string):
            subtitle = L(count: string.count, one: "item.text.one", many: "item.text.many")
            toolTip = string.count > 400 ? String(string.prefix(400)) + "…" : string
        }
    }

    /// What kind of thing a file is, in the words Finder uses: "PDF document", "Folder".
    private static func kind(of item: StashItem, path: String) -> String {
        if item.kind == .folder { return L("item.kind.folder") }
        let type = UTType(filenameExtension: (path as NSString).pathExtension)
        return type?.localizedDescription?.capitalizedFirst ?? L("item.kind.file")
    }
}

private extension String {
    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}

/// An image for a row. Symbols are drawn in the text colour; file icons and thumbnails as they are.
struct ItemIcon {
    let image: NSImage?
    let isSymbol: Bool
}

/// Finds the image for each item: the system's own icon for the file at first, then a
/// thumbnail of its content when the system can make one.
@MainActor
final class ItemImages {
    private var thumbnails: [UUID: NSImage] = [:]
    private var requested: Set<UUID> = []

    /// `whenBetter` is called if a thumbnail arrives after the plain icon has been returned.
    func icon(for item: StashItem, at url: URL?, whenBetter: @escaping @MainActor () -> Void) -> ItemIcon {
        switch item.content {
        case .link:
            return symbol("link")
        case .text:
            return symbol("text.alignleft")
        case .reference(_, let path):
            return fileIcon(for: item, at: url, lastKnownPath: path, whenBetter: whenBetter)
        case .copy:
            return fileIcon(for: item, at: url, lastKnownPath: item.name, whenBetter: whenBetter)
        }
    }

    /// Drops the thumbnails of items that are no longer on the shelf.
    func forget(except ids: Set<UUID>) {
        thumbnails = thumbnails.filter { ids.contains($0.key) }
        requested.formIntersection(ids)
    }

    private func symbol(_ name: String) -> ItemIcon {
        let configuration = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        return ItemIcon(image: image, isSymbol: true)
    }

    private func fileIcon(
        for item: StashItem, at url: URL?, lastKnownPath: String, whenBetter: @escaping @MainActor () -> Void
    ) -> ItemIcon {
        guard let url else {
            // The file cannot be found. Show what kind of file it was.
            let type = item.kind == .folder
                ? UTType.folder
                : UTType(filenameExtension: (lastKnownPath as NSString).pathExtension) ?? .data
            return ItemIcon(image: NSWorkspace.shared.icon(for: type), isSymbol: false)
        }
        if let thumbnail = thumbnails[item.id] {
            return ItemIcon(image: thumbnail, isSymbol: false)
        }
        if item.kind != .folder, requested.insert(item.id).inserted {
            requestThumbnail(for: item.id, at: url, whenBetter: whenBetter)
        }
        return ItemIcon(image: NSWorkspace.shared.icon(forFile: url.path), isSymbol: false)
    }

    private func requestThumbnail(for id: UUID, at url: URL, whenBetter: @escaping @MainActor () -> Void) {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: 32, height: 32), scale: scale, representationTypes: .thumbnail)
        // Drawn as Finder draws it: a page with its content on it, not a bare picture.
        request.iconMode = true
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            guard let cgImage = representation?.cgImage else { return }
            Task { @MainActor in
                guard let self, self.requested.contains(id) else { return }
                let size = NSSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale)
                self.thumbnails[id] = NSImage(cgImage: cgImage, size: size)
                whenBetter()
            }
        }
    }
}
