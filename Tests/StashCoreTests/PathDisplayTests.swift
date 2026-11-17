import Foundation
import Testing
@testable import StashCore

@Suite struct PathDisplayTests {
    @Test func theHomeFolderIsWrittenAsATilde() {
        #expect(PathDisplay.abbreviate("/Users/anna/Documents/a.pdf", home: "/Users/anna") == "~/Documents/a.pdf")
        #expect(PathDisplay.abbreviate("/Users/anna", home: "/Users/anna") == "~")
        #expect(PathDisplay.abbreviate("/Users/anna", home: "/Users/anna/") == "~")
    }

    @Test func otherPathsAreLeftAlone() {
        #expect(PathDisplay.abbreviate("/Users/annabel/a.pdf", home: "/Users/anna") == "/Users/annabel/a.pdf")
        #expect(PathDisplay.abbreviate("/Volumes/Disk/a.pdf", home: "/Users/anna") == "/Volumes/Disk/a.pdf")
        #expect(PathDisplay.abbreviate("/a.pdf", home: "") == "/a.pdf")
    }

    @Test func theFolderOfAFile() {
        #expect(PathDisplay.folder(ofPath: "/Users/anna/Documents/a.pdf", home: "/Users/anna") == "~/Documents")
        #expect(PathDisplay.folder(ofPath: "/Users/anna/a.pdf", home: "/Users/anna") == "~")
        #expect(PathDisplay.folder(ofPath: "/a.pdf", home: "/Users/anna") == "/")
    }

    @Test func theRealHomeFolderIsNotASandboxContainer() {
        #expect(!PathDisplay.home.contains("/Library/Containers/"))
        #expect(PathDisplay.home.hasPrefix("/"))
    }

    @Test func trashFolders() {
        #expect(PathDisplay.isInTrash("/Users/anna/.Trash/a.pdf"))
        #expect(PathDisplay.isInTrash("/Volumes/Disk/.Trashes/501/a.pdf"))
        #expect(!PathDisplay.isInTrash("/Users/anna/Trash/a.pdf"))
        #expect(!PathDisplay.isInTrash("/Users/anna/.Trashy/a.pdf"))
    }

    @Test func temporaryPlaces() {
        #expect(PathDisplay.isTemporary("/private/var/folders/ab/xyz/T/TemporaryItems/NSIRD_screencaptureui_1/Screenshot.png"))
        #expect(PathDisplay.isTemporary("/var/folders/ab/xyz/T/file.txt"))
        #expect(PathDisplay.isTemporary("/private/tmp/file.txt"))
        #expect(PathDisplay.isTemporary("/tmp/file.txt"))
        #expect(PathDisplay.isTemporary("/Users/anna/Library/Caches/com.example/file.txt"))
        #expect(PathDisplay.isTemporary("/Users/anna/Library/Containers/com.example/Data/tmp/file.txt"))
        #expect(!PathDisplay.isTemporary("/Users/anna/Documents/file.txt"))
        #expect(!PathDisplay.isTemporary("/Users/anna/tmpfiles/file.txt"))
        #expect(!PathDisplay.isTemporary("/Volumes/Disk/Caches.txt"))
    }

    @Test func aTitleForText() {
        #expect(PathDisplay.title(forText: "one\ntwo") == "one")
        #expect(PathDisplay.title(forText: "\n\n   \n  padded  \nnext") == "padded")
        #expect(PathDisplay.title(forText: "") == "")
        #expect(PathDisplay.title(forText: String(repeating: "a", count: 100), limit: 10) == "aaaaaaaaaa…")
        #expect(PathDisplay.title(forText: "exactly ten", limit: 11) == "exactly ten")
    }

    @Test func aCompactLink() {
        #expect(PathDisplay.compact(URL(string: "https://example.com/")!) == "example.com")
        #expect(PathDisplay.compact(URL(string: "http://example.com/a/b?c=d")!) == "example.com/a/b?c=d")
        #expect(PathDisplay.compact(URL(string: "mailto:a@example.com")!) == "mailto:a@example.com")
    }
}
