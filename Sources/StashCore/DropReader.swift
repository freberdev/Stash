import AppKit
import UniformTypeIdentifiers

/// Something dropped that is not a file on disk.
public enum DropPiece: Equatable, Sendable {
    case image(data: Data, fileExtension: String)
    case link(url: URL, title: String?)
    case text(String)
}

/// What a drop contains, in the form Stash can keep it.
public enum DropContent: Equatable {
    /// Files and folders that exist on disk. They are kept as references.
    case files([URL])
    /// Files the source app has promised to write, such as an attachment dragged out of Mail.
    /// The caller collects them with `DropReader.promiseReceivers(on:)`.
    case promisedFiles
    case pieces([DropPiece])
    /// Nothing Stash knows how to keep.
    case nothing
}

/// Works out what is on a pasteboard during a drop.
///
/// Apps describe the same drag in several ways at once. The order here decides which
/// description wins: a real file before a promised file, before image data, a link and plain text.
@MainActor
public enum DropReader {
    private static let urlName = NSPasteboard.PasteboardType("public.url-name")

    private static let imageTypes: [(type: NSPasteboard.PasteboardType, fileExtension: String)] = [
        (.png, "png"),
        (NSPasteboard.PasteboardType(UTType.jpeg.identifier), "jpg"),
        (NSPasteboard.PasteboardType(UTType.gif.identifier), "gif"),
        (NSPasteboard.PasteboardType(UTType.heic.identifier), "heic"),
        (.tiff, "tiff"),
    ]

    /// The pasteboard types a drop target must register for.
    public static var acceptedTypes: [NSPasteboard.PasteboardType] {
        [.fileURL, .URL, .string] + imageTypes.map(\.type)
            + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
    }

    public static func read(_ pasteboard: NSPasteboard) -> DropContent {
        let files = pasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if !files.isEmpty { return .files(files) }

        if !promiseReceivers(on: pasteboard).isEmpty { return .promisedFiles }

        let pieces = (pasteboard.pasteboardItems ?? []).compactMap(piece)
        return pieces.isEmpty ? .nothing : .pieces(pieces)
    }

    /// The promised files on the pasteboard that are worth collecting.
    public static func promiseReceivers(on pasteboard: NSPasteboard) -> [NSFilePromiseReceiver] {
        let receivers = pasteboard.readObjects(
            forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver] ?? []
        return receivers.filter { !isOnlyLinkFiles($0.fileTypes) }
    }

    /// A browser that drags a link may promise a link file as well. The link itself is the better thing to keep.
    static func isOnlyLinkFiles(_ fileTypes: [String]) -> Bool {
        guard !fileTypes.isEmpty else { return true }
        return fileTypes.allSatisfy { identifier in
            guard let type = UTType(identifier) ?? UTType(filenameExtension: identifier) else { return false }
            return [UTType.internetLocation, .internetShortcut, .url].contains { type.conforms(to: $0) }
        }
    }

    static func piece(from item: NSPasteboardItem) -> DropPiece? {
        let text = item.string(forType: .string)
        let link = item.string(forType: .URL).flatMap(Self.link)
        let image = imageTypes.lazy.compactMap { entry -> DropPiece? in
            guard let data = item.data(forType: entry.type), !data.isEmpty else { return nil }
            return .image(data: data, fileExtension: entry.fileExtension)
        }.first

        // An image dragged from a web page comes with its address. Text that comes with a
        // picture of itself is still text.
        let textIsAnAddress = text.flatMap(webAddress) != nil
        if let image, text == nil || link != nil || textIsAnAddress {
            return image
        }
        if let link {
            return .link(url: link, title: item.string(forType: urlName))
        }
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let address = webAddress(text) { return .link(url: address, title: nil) }
            return .text(text)
        }
        return image
    }

    /// A link from a pasteboard's URL type. File URLs are handled as files, not links.
    private static func link(_ string: String) -> URL? {
        guard let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme, !scheme.isEmpty, !url.isFileURL
        else { return nil }
        return url
    }

    /// A piece of text that is nothing but a web address.
    static func webAddress(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace),
              let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host?.isEmpty == false
        else { return nil }
        return url
    }
}
