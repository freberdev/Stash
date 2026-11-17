import Foundation
import Testing
@testable import StashCore

@MainActor @Suite struct ItemStoreTests {
    let temp = TempDirectory()
    let clock = TestClock()

    /// The test files live in the system's temporary folder. Unless a test says otherwise,
    /// nothing is treated as temporary, so they behave like files in the user's own folders.
    func makeStore(temporary: @escaping (String) -> Bool = { _ in false }) -> ItemStore {
        let store = ItemStore(directory: temp.shelf, now: { [clock] in clock.now }, isTemporary: temporary)
        store.load()
        return store
    }

    // MARK: Files and folders

    @Test func addingAFilePutsAReferenceOnTheShelf() {
        let file = temp.makeFile("Report.pdf")
        let store = makeStore()

        #expect(store.addFiles([file]) == AddOutcome(added: 1))

        #expect(store.items.count == 1)
        #expect(store.items[0].name == "Report.pdf")
        #expect(store.items[0].kind == .file)
        #expect(store.items[0].isReference)
        #expect(store.items[0].added == clock.now)
        #expect(store.fileURL(for: store.items[0])?.path == file.path)
        #expect(store.missing.isEmpty)
    }

    @Test func aFolderIsAFolder() {
        let folder = temp.makeFolder("Project")
        let store = makeStore()
        store.addFiles([folder])
        #expect(store.items[0].kind == .folder)
        #expect(store.items[0].name == "Project")
    }

    @Test func nothingIsCopiedIntoTheShelfForAFile() {
        let file = temp.makeFile("Big.bin", content: String(repeating: "x", count: 100_000))
        let store = makeStore()
        store.addFiles([file])
        #expect(!FileManager.default.fileExists(atPath: store.copiesDirectory.path))
    }

    @Test func theOriginalIsNeverTouched() {
        let file = temp.makeFile("Original.txt", content: "leave me alone")
        let before = FileFingerprint(file)
        let store = makeStore()

        store.addFiles([file])
        store.refresh()
        store.markUsed([store.items[0].id])
        store.remove([store.items[0].id])
        store.undo()
        store.clear()
        store.forgetRemoved()
        clock.advance(days: 40)
        store.addFiles([file])
        store.removeExpired(.oneDay)

        #expect(FileFingerprint(file) == before)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func newFilesGoOnTopInTheOrderTheyWereDropped() {
        let store = makeStore()
        store.addFiles([temp.makeFile("old.txt")])
        store.addFiles([temp.makeFile("a.txt"), temp.makeFile("b.txt")])
        #expect(store.items.map(\.name) == ["a.txt", "b.txt", "old.txt"])
    }

    @Test func aFileAlreadyOnTheShelfMovesToTheTopInsteadOfBeingAddedTwice() {
        let first = temp.makeFile("first.txt"), second = temp.makeFile("second.txt")
        let store = makeStore()
        store.addFiles([first])
        store.addFiles([second])

        #expect(store.addFiles([first]) == AddOutcome(alreadyThere: 1))
        #expect(store.items.map(\.name) == ["first.txt", "second.txt"])
    }

    @Test func theSameFileTwiceInOneDropIsAddedOnce() {
        let file = temp.makeFile("twice.txt")
        let store = makeStore()
        #expect(store.addFiles([file, file]) == AddOutcome(added: 1, alreadyThere: 1))
        #expect(store.items.count == 1)
    }

    @Test func aFileThatDoesNotExistCannotBeAdded() {
        let store = makeStore()
        let outcome = store.addFiles([temp.url.appendingPathComponent("nowhere.txt")])
        #expect(outcome == AddOutcome(failed: 1))
        #expect(store.items.isEmpty)
    }

    // MARK: Between launches

    @Test func theShelfIsStillThereAfterARestart() {
        let file = temp.makeFile("kept.txt")
        let first = makeStore()
        first.addFiles([file])
        first.addLink(URL(string: "https://example.com/page")!, title: "Example")
        first.addText("some text")

        let second = makeStore()
        #expect(second.items == first.items)
        #expect(second.items.map(\.kind) == [.text, .link, .file])
        #expect(second.fileURL(for: second.items[2])?.path == file.path)
        #expect(second.missing.isEmpty)
    }

    @Test func theListIsReadableOnlyByTheUser() throws {
        let store = makeStore()
        store.addText("private")
        let file = temp.shelf.appendingPathComponent("items.json")
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let folder = try FileManager.default.attributesOfItem(atPath: temp.shelf.path)
        #expect((folder[.posixPermissions] as? NSNumber)?.intValue == 0o700)
    }

    @Test func aListThatCannotBeReadIsPutAsideNotOverwritten() throws {
        let first = makeStore()
        first.addImage(Data([1, 2, 3]), fileName: "Image.png")
        let list = temp.shelf.appendingPathComponent("items.json")
        try Data("not json".utf8).write(to: list)

        let second = makeStore()
        #expect(second.items.isEmpty)
        let aside = temp.shelf.appendingPathComponent("items.unreadable.json")
        #expect(try String(contentsOf: aside, encoding: .utf8) == "not json")
        // The copies may belong to the list that could not be read. They are left alone.
        let copies = try FileManager.default.contentsOfDirectory(atPath: second.copiesDirectory.path)
        #expect(copies.count == 1)
    }

    @Test func copiesSurviveEveryLaunchAfterAListThatCouldNotBeRead() throws {
        let first = makeStore()
        first.addImage(Data([1, 2, 3]), fileName: "Image.png")
        try Data("not json".utf8).write(to: temp.shelf.appendingPathComponent("items.json"))

        _ = makeStore()
        let third = makeStore()
        #expect(third.items.isEmpty)
        // As long as the list that was put aside is there, its copies are too.
        #expect(try FileManager.default.contentsOfDirectory(atPath: third.copiesDirectory.path).count == 1)
    }

    @Test func aListThatExistsButCannotBeOpenedIsNotTakenForAnEmptyShelf() throws {
        let first = makeStore()
        first.addImage(Data([1, 2, 3]), fileName: "Image.png")
        let list = temp.shelf.appendingPathComponent("items.json")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: list.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: list.path) }

        let second = makeStore()
        #expect(second.items.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: second.copiesDirectory.path).count == 1)
    }

    @Test func aListFromANewerVersionIsPutAside() throws {
        try FileManager.default.createDirectory(at: temp.shelf, withIntermediateDirectories: true)
        let list = temp.shelf.appendingPathComponent("items.json")
        try Data(#"{"version": 99, "items": []}"#.utf8).write(to: list)

        let store = makeStore()
        #expect(store.items.isEmpty)
        #expect(FileManager.default.fileExists(atPath: temp.shelf.appendingPathComponent("items.unreadable.json").path))
    }

    @Test func aFailedSaveIsReported() throws {
        // A file where the shelf's folder should be makes every save fail.
        try Data().write(to: temp.shelf)
        let store = makeStore()
        store.addText("cannot be saved")
        #expect(store.saveFailed)
        #expect(store.items.count == 1)
    }

    // MARK: Files that change underneath

    @Test func aRenamedFileIsFollowed() throws {
        let file = temp.makeFile("before.txt")
        let store = makeStore()
        store.addFiles([file])

        let renamed = temp.url.appendingPathComponent("after.txt")
        try FileManager.default.moveItem(at: file, to: renamed)
        store.refresh()

        #expect(store.missing.isEmpty)
        #expect(store.items[0].name == "after.txt")
        #expect(store.fileURL(for: store.items[0])?.path == renamed.path)
    }

    @Test func aMovedFileIsFollowedAlsoAfterARestart() throws {
        let file = temp.makeFile("moving.txt")
        makeStore().addFiles([file])

        let moved = temp.makeFolder("Elsewhere").appendingPathComponent("moving.txt")
        try FileManager.default.moveItem(at: file, to: moved)

        let store = makeStore()
        #expect(store.missing.isEmpty)
        #expect(store.fileURL(for: store.items[0])?.path == moved.path)
        guard case .reference(_, let path) = store.items[0].content else {
            Issue.record("not a reference")
            return
        }
        #expect(path == moved.path)
    }

    @Test func aDeletedFileIsShownAsMissingAndCanBeRemoved() throws {
        let file = temp.makeFile("doomed.txt")
        let store = makeStore()
        store.addFiles([file])

        try FileManager.default.removeItem(at: file)
        store.refresh()

        let item = store.items[0]
        #expect(store.missing == [item.id])
        #expect(store.fileURL(for: item) == nil)
        #expect(item.name == "doomed.txt")

        store.remove([item.id])
        #expect(store.items.isEmpty)
        #expect(store.missing.isEmpty)
    }

    @Test func aFileInTheTrashCountsAsMissing() throws {
        let file = temp.makeFile("trashed.txt")
        let store = makeStore()
        store.addFiles([file])

        let trash = temp.makeFolder(".Trash")
        try FileManager.default.moveItem(at: file, to: trash.appendingPathComponent("trashed.txt"))
        store.refresh()
        #expect(store.missing == [store.items[0].id])

        // Put back, it is available again.
        try FileManager.default.moveItem(at: trash.appendingPathComponent("trashed.txt"), to: file)
        store.refresh()
        #expect(store.missing.isEmpty)
        #expect(store.fileURL(for: store.items[0])?.path == file.path)
    }

    @Test func droppingAMissingFileAgainRepairsTheRow() throws {
        let file = temp.makeFile("back.txt")
        let store = makeStore()
        store.addFiles([file])
        try FileManager.default.removeItem(at: file)
        store.refresh()
        #expect(store.missing.count == 1)

        temp.makeFile("back.txt", content: "a new file with the old name")
        #expect(store.addFiles([file]) == AddOutcome(alreadyThere: 1))
        #expect(store.items.count == 1)
        #expect(store.missing.isEmpty)
        #expect(store.fileURL(for: store.items[0])?.path == file.path)
    }

    // MARK: Files that will not last

    @Test func aFileInATemporaryFolderIsKeptAsACopy() throws {
        // A screenshot dragged from its floating thumbnail, for example, is deleted by the system later.
        let file = temp.makeFile("TemporaryItems/Screenshot.png", content: "pixels")
        let before = FileFingerprint(file)
        let store = makeStore(temporary: { $0.contains("/TemporaryItems/") })

        #expect(store.addFiles([file]) == AddOutcome(added: 1))
        let item = store.items[0]
        #expect(item.isCopy)
        #expect(item.kind == .image)
        #expect(item.name == "Screenshot.png")

        // The source may delete its file. Stash still has the content.
        #expect(FileFingerprint(file) == before)
        try FileManager.default.removeItem(at: file)
        store.refresh()
        #expect(store.missing.isEmpty)
        #expect(try String(contentsOf: #require(store.fileURL(for: item)), encoding: .utf8) == "pixels")
    }

    @Test func otherFilesInTheSameDropAreStillReferences() {
        let lasting = temp.makeFile("lasting.txt")
        let passing = temp.makeFile("TemporaryItems/passing.txt")
        let store = makeStore(temporary: { $0.contains("/TemporaryItems/") })

        #expect(store.addFiles([lasting, passing]) == AddOutcome(added: 2))
        #expect(store.items.map(\.name) == ["lasting.txt", "passing.txt"])
        #expect(store.items[0].isReference)
        #expect(store.items[1].isCopy)
    }

    // MARK: Links and text

    @Test func aLinkIsNamedByItsTitleOrItsHost() {
        let store = makeStore()
        store.addLink(URL(string: "https://example.com/a")!, title: "  A page  ")
        store.addLink(URL(string: "https://example.org/b")!, title: " ")
        store.addLink(URL(string: "https://example.net/c")!)
        #expect(store.items.map(\.name) == ["example.net", "example.org", "A page"])
        #expect(store.items.allSatisfy { $0.kind == .link && !$0.isReference && !$0.isCopy })
    }

    @Test func theSameLinkOrTextMovesToTheTop() {
        let store = makeStore()
        let link = URL(string: "https://example.com")!
        store.addLink(link)
        store.addText("hello")
        #expect(store.addLink(link) == AddOutcome(alreadyThere: 1))
        #expect(store.items.map(\.kind) == [.link, .text])
        #expect(store.addText("hello") == AddOutcome(alreadyThere: 1))
        #expect(store.items.map(\.kind) == [.text, .link])
    }

    @Test func textIsNamedByItsFirstLine() {
        let store = makeStore()
        store.addText("\n  first line  \nsecond line")
        #expect(store.items[0].name == "first line")
        #expect(store.items[0].content == .text(string: "\n  first line  \nsecond line"))
    }

    @Test func emptyTextIsNotAdded() {
        let store = makeStore()
        #expect(store.addText("  \n\t ") == AddOutcome(failed: 1))
        #expect(store.items.isEmpty)
    }

    // MARK: Copies

    @Test func imageDataIsKeptAsACopy() throws {
        let store = makeStore()
        #expect(store.addImage(Data([9, 8, 7]), fileName: "Image.png") == AddOutcome(added: 1))

        let item = store.items[0]
        #expect(item.kind == .image)
        #expect(item.isCopy)
        let file = try #require(store.fileURL(for: item))
        #expect(file.path.hasPrefix(store.copiesDirectory.path))
        #expect(try Data(contentsOf: file) == Data([9, 8, 7]))
    }

    @Test func aDeliveredFileThatIsNotAnImageIsAFile() throws {
        let store = makeStore()
        let file = try store.makeCopyDirectory().appendingPathComponent("Invoice.pdf")
        try Data("pdf".utf8).write(to: file)
        #expect(store.addCopy(at: file) == AddOutcome(added: 1))
        #expect(store.items[0].kind == .file)
        #expect(store.items[0].name == "Invoice.pdf")
    }

    @Test func aFileOutsideTheCopiesFolderIsNotTakenAsACopy() {
        let store = makeStore()
        #expect(store.addCopy(at: temp.makeFile("stray.txt")) == AddOutcome(failed: 1))
        #expect(store.items.isEmpty)
    }

    @Test func aRemovedCopyIsDeletedOnlyWhenUndoIsGivenUp() throws {
        let store = makeStore()
        store.addImage(Data([1]), fileName: "Image.png")
        let file = try #require(store.fileURL(for: store.items[0]))

        store.remove([store.items[0].id])
        #expect(FileManager.default.fileExists(atPath: file.path))

        store.undo()
        #expect(store.items.count == 1)
        #expect(store.missing.isEmpty)

        store.remove([store.items[0].id])
        store.forgetRemoved()
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(!FileManager.default.fileExists(atPath: file.deletingLastPathComponent().path))
        #expect(!store.canUndo)
    }

    @Test func copiesNoItemRefersToAreRemovedAtLaunch() throws {
        let first = makeStore()
        first.addImage(Data([1]), fileName: "Kept.png")
        let orphan = try first.makeCopyDirectory().appendingPathComponent("Orphan.png")
        try Data([2]).write(to: orphan)

        let second = makeStore()
        #expect(!FileManager.default.fileExists(atPath: orphan.deletingLastPathComponent().path))
        #expect(second.fileURL(for: second.items[0]).map { FileManager.default.fileExists(atPath: $0.path) } == true)
    }

    @Test func aCopyWhoseFileIsGoneIsMissing() throws {
        let store = makeStore()
        store.addImage(Data([1]), fileName: "Image.png")
        try FileManager.default.removeItem(at: #require(store.fileURL(for: store.items[0])))
        store.refresh()
        #expect(store.missing == [store.items[0].id])
    }

    // MARK: Removing and undoing

    @Test func removingAndUndoingPutsItemsBackWhereTheyWere() {
        let store = makeStore()
        for text in ["e", "d", "c", "b", "a"] { store.addText(text) }
        let ids = store.items.map(\.id)

        #expect(store.remove([ids[1], ids[3]]) == 2)
        #expect(store.items.map(\.name) == ["a", "c", "e"])
        #expect(store.canUndo)

        #expect(store.undo() == 2)
        #expect(store.items.map(\.name) == ["a", "b", "c", "d", "e"])
        #expect(!store.canUndo)
        #expect(makeStore().items.map(\.name) == ["a", "b", "c", "d", "e"])
    }

    @Test func undoTakesBackOneRemovalAtATime() {
        let store = makeStore()
        for text in ["c", "b", "a"] { store.addText(text) }
        store.remove([store.items[0].id])
        store.remove([store.items[0].id])
        #expect(store.undoDepth == 2)

        store.undo()
        #expect(store.items.map(\.name) == ["b", "c"])
        store.undo()
        #expect(store.items.map(\.name) == ["a", "b", "c"])
        #expect(store.undo() == 0)
    }

    @Test func clearingCanBeUndone() {
        let file = temp.makeFile("f.txt")
        let store = makeStore()
        store.addFiles([file])
        store.addText("t")

        #expect(store.clear() == 2)
        #expect(store.items.isEmpty)
        #expect(makeStore().items.isEmpty)

        store.undo()
        #expect(store.items.map(\.name) == ["t", "f.txt"])
        #expect(store.fileURL(for: store.items[1])?.path == file.path)
    }

    @Test func undoDoesNotBringBackWhatHasBeenAddedAgainSince() {
        let file = temp.makeFile("again.txt")
        let link = URL(string: "https://example.com")!
        let store = makeStore()
        store.addFiles([file])
        store.addLink(link)
        store.addText("words")
        store.addText("other")
        store.remove(Set(store.items.filter { $0.name != "other" }.map(\.id)))

        store.addFiles([file])
        store.addLink(link)
        store.addText("words")
        #expect(store.undo() == 0)
        #expect(store.items.count == 4)
        #expect(Set(store.items.map(\.name)).count == 4)
    }

    @Test func itemsThatWouldBeClearedCanBeCountedFirst() {
        let store = makeStore()
        store.addText("old")
        clock.advance(days: 2)
        store.addText("new")
        #expect(store.expiredCount(.oneDay) == 1)
        #expect(store.expiredCount(.oneWeek) == 0)
        #expect(store.expiredCount(.never) == 0)
        #expect(store.items.count == 2)
    }

    @Test func removingNothingLeavesNothingToUndo() {
        let store = makeStore()
        #expect(store.remove([UUID()]) == 0)
        #expect(store.clear() == 0)
        #expect(!store.canUndo)
    }

    // MARK: Clearing by age

    @Test func itemsOlderThanTheChosenTimeAreCleared() {
        let store = makeStore()
        store.addText("old")
        clock.advance(days: 5)
        store.addText("newer")
        clock.advance(days: 3)

        #expect(store.removeExpired(.never) == 0)
        #expect(store.removeExpired(.oneMonth) == 0)
        #expect(store.removeExpired(.oneWeek) == 1)
        #expect(store.items.map(\.name) == ["newer"])
        // Clearing by age is not something to undo.
        #expect(!store.canUndo)
        #expect(makeStore().items.map(\.name) == ["newer"])
    }

    @Test func clearingByAgeDeletesCopiesButNeverOriginals() throws {
        let original = temp.makeFile("original.txt")
        let store = makeStore()
        store.addFiles([original])
        store.addImage(Data([1]), fileName: "Image.png")
        let copy = try #require(store.fileURL(for: store.items[0]))
        clock.advance(days: 2)

        #expect(store.removeExpired(.oneDay) == 2)
        #expect(!FileManager.default.fileExists(atPath: copy.path))
        #expect(FileManager.default.fileExists(atPath: original.path))
    }

    // MARK: Use

    @Test func usingAnItemIsRemembered() {
        let store = makeStore()
        store.addText("used")
        #expect(store.items[0].lastUsed == nil)
        clock.advance(days: 1)
        store.markUsed([store.items[0].id])
        #expect(store.items[0].lastUsed == clock.now)
        #expect(makeStore().items[0].lastUsed == clock.now)
    }
}
