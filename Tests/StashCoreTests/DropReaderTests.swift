import AppKit
import Testing
@testable import StashCore

/// Each test fills a private pasteboard the way a source app would during a drag.
@MainActor @Suite struct DropReaderTests {
    final class Board {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("stash-tests-\(UUID().uuidString)"))
        deinit { pasteboard.releaseGlobally() }

        func write(_ objects: [any NSPasteboardWriting]) {
            pasteboard.clearContents()
            pasteboard.writeObjects(objects)
        }
    }

    let board = Board()
    let temp = TempDirectory()

    static let urlName = NSPasteboard.PasteboardType("public.url-name")
    static let rtf = NSPasteboard.PasteboardType.rtf

    func item(_ strings: [NSPasteboard.PasteboardType: String] = [:], data: [NSPasteboard.PasteboardType: Data] = [:])
        -> NSPasteboardItem
    {
        let item = NSPasteboardItem()
        for (type, value) in strings { item.setString(value, forType: type) }
        for (type, value) in data { item.setData(value, forType: type) }
        return item
    }

    // MARK: Files

    @Test func filesFromFinderAreFiles() {
        let a = temp.makeFile("a.txt"), b = temp.makeFolder("Folder")
        board.write([a as NSURL, b as NSURL])
        #expect(DropReader.read(board.pasteboard) == .files([a, b]))
    }

    @Test func aFileWinsOverItsOwnNameAsText() {
        let file = temp.makeFile("a.txt")
        let entry = item([.fileURL: file.absoluteString, .string: "a.txt"])
        board.write([entry])
        #expect(DropReader.read(board.pasteboard) == .files([file]))
    }

    // MARK: Links

    @Test func aLinkFromABrowserKeepsItsTitle() {
        board.write([item([
            .URL: "https://example.com/article", Self.urlName: "An article", .string: "https://example.com/article",
        ])])
        #expect(DropReader.read(board.pasteboard) == .pieces([
            .link(url: URL(string: "https://example.com/article")!, title: "An article"),
        ]))
    }

    @Test func aLinkWithoutATitleIsStillALink() {
        board.write([item([.URL: "mailto:someone@example.com"])])
        #expect(DropReader.read(board.pasteboard) == .pieces([
            .link(url: URL(string: "mailto:someone@example.com")!, title: nil),
        ]))
    }

    @Test func textThatIsOnlyAWebAddressBecomesALink() {
        board.write([item([.string: "  https://example.com/path?q=1 \n"])])
        #expect(DropReader.read(board.pasteboard) == .pieces([
            .link(url: URL(string: "https://example.com/path?q=1")!, title: nil),
        ]))
    }

    // MARK: Text

    @Test func selectedTextIsText() {
        board.write([item([.string: "Two words", Self.rtf: "{\\rtf1 Two words}"])])
        #expect(DropReader.read(board.pasteboard) == .pieces([.text("Two words")]))
    }

    @Test func textThatMentionsAnAddressIsStillText() {
        board.write([item([.string: "See https://example.com for more"])])
        #expect(DropReader.read(board.pasteboard) == .pieces([.text("See https://example.com for more")]))
    }

    @Test func textKeepsItsLineBreaksAndSpaces() {
        board.write([item([.string: "  line one\n\tline two  "])])
        #expect(DropReader.read(board.pasteboard) == .pieces([.text("  line one\n\tline two  ")]))
    }

    @Test func blankTextIsNothing() {
        board.write([item([.string: " \n "])])
        #expect(DropReader.read(board.pasteboard) == .nothing)
    }

    // MARK: Images

    @Test func imageDataIsAnImage() {
        board.write([item(data: [.png: Data([1, 2, 3])])])
        #expect(DropReader.read(board.pasteboard) == .pieces([.image(data: Data([1, 2, 3]), fileExtension: "png")]))
    }

    @Test func pngIsPreferredOverTiff() {
        board.write([item(data: [.tiff: Data([4]), .png: Data([5])])])
        #expect(DropReader.read(board.pasteboard) == .pieces([.image(data: Data([5]), fileExtension: "png")]))
    }

    @Test func anImageFromAWebPageIsAnImageNotItsAddress() {
        board.write([item(
            [.URL: "https://example.com/photo.jpg", .string: "https://example.com/photo.jpg"],
            data: [.tiff: Data([6])])])
        #expect(DropReader.read(board.pasteboard) == .pieces([.image(data: Data([6]), fileExtension: "tiff")]))
    }

    @Test func textThatComesWithAPictureOfItselfIsText() {
        board.write([item([.string: "A sentence"], data: [.tiff: Data([7])])])
        #expect(DropReader.read(board.pasteboard) == .pieces([.text("A sentence")]))
    }

    // MARK: Several things, and nothing

    @Test func everyItemInADragIsRead() {
        board.write([item([.string: "one"]), item([.URL: "https://example.com"]), item([.string: "three"])])
        #expect(DropReader.read(board.pasteboard) == .pieces([
            .text("one"), .link(url: URL(string: "https://example.com")!, title: nil), .text("three"),
        ]))
    }

    @Test func anEmptyPasteboardIsNothing() {
        board.pasteboard.clearContents()
        #expect(DropReader.read(board.pasteboard) == .nothing)
    }

    @Test func somethingUnknownIsNothing() {
        board.write([item(data: [NSPasteboard.PasteboardType("com.example.private"): Data([1])])])
        #expect(DropReader.read(board.pasteboard) == .nothing)
    }

    // MARK: Promised files

    @Test func aPromisedLinkFileIsNotWorthCollecting() {
        #expect(DropReader.isOnlyLinkFiles(["com.apple.web-internet-location"]))
        #expect(DropReader.isOnlyLinkFiles(["webloc"]))
        #expect(DropReader.isOnlyLinkFiles([]))
    }

    @Test func otherPromisedFilesAre() {
        #expect(!DropReader.isOnlyLinkFiles(["public.jpeg"]))
        #expect(!DropReader.isOnlyLinkFiles(["pdf"]))
        #expect(!DropReader.isOnlyLinkFiles(["com.apple.web-internet-location", "public.png"]))
        #expect(!DropReader.isOnlyLinkFiles(["something.unknown"]))
    }

    @Test func aPromisedFileIsRecognised() {
        let provider = NSFilePromiseProvider(fileType: "public.plain-text", delegate: PromiseStub())
        board.write([provider])
        #expect(DropReader.read(board.pasteboard) == .promisedFiles)
        #expect(DropReader.promiseReceivers(on: board.pasteboard).count == 1)
    }

    // MARK: Web addresses

    @Test func webAddresses() {
        #expect(DropReader.webAddress("https://example.com") != nil)
        #expect(DropReader.webAddress("HTTP://example.com/a b") == nil)
        #expect(DropReader.webAddress("example.com") == nil)
        #expect(DropReader.webAddress("ftp://example.com") == nil)
        #expect(DropReader.webAddress("https://") == nil)
        #expect(DropReader.webAddress("") == nil)
    }

    // MARK: What a drop target registers for

    @Test func acceptedTypesCoverFilesLinksTextImagesAndPromises() {
        let types = DropReader.acceptedTypes
        for expected in [NSPasteboard.PasteboardType.fileURL, .URL, .string, .png, .tiff] {
            #expect(types.contains(expected))
        }
        #expect(types.count > 5)
    }
}

private final class PromiseStub: NSObject, NSFilePromiseProviderDelegate {
    func filePromiseProvider(_ provider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        "promised.txt"
    }

    func filePromiseProvider(
        _ provider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping (Error?) -> Void
    ) {
        completionHandler(nil)
    }
}
