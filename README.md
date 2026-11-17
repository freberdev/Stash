# Stash

A small shelf for macOS that holds what you need for the task at hand. Drag files, folders, links, images and text onto it while you work, drag them out again when you need them, and clear it when you are done.

Stash is not a file manager and not an archive. It is a temporary surface next to your work, like the corner of a desk.

- Lives in the menu bar and opens with a click or a global shortcut, ⌃⌥S by default.
- A floating panel that stays above other windows without taking over the app you are in.
- Files and folders are kept as references. The originals stay where they are.
- Drag out to Finder or any other app, one item or several at once.
- Remove one item or clear everything, with undo.
- The shelf is still there after a restart.
- Optionally clears itself after a day, a week or 30 days.
- English and Swedish, light and dark.
- Runs in the App Sandbox with read-only access and no network access.

Requires macOS 26 or later.

## Using Stash

Click the tray icon in the menu bar, or press the shortcut, to show the shelf. Drag things onto it. You can also drop straight onto the icon in the menu bar; the shelf then opens to show what landed.

Drag a row out to use it somewhere else. Select several rows to drag them together. Double-click opens a file or a link in its default app, and puts a piece of text on the clipboard.

| Key | What it does |
|---|---|
| ⌃⌥S (configurable) | Show or hide the shelf from anywhere |
| ↑ ↓ | Move through the list |
| Return | Open the selected items |
| ⌫ | Remove the selected items from the shelf |
| ⌘Z | Put back what was just removed |
| ⌘C | Copy the selected items |
| ⌘A | Select everything |
| ⌘, | Settings |
| Esc, ⌘W | Hide the shelf |

A right-click on a row offers Open, Show in Finder, Copy and Remove from Stash. A right-click on the icon in the menu bar offers Clear Stash, Settings and Quit.

Removing and clearing happen at once, without a question. **Undo** stays in the bottom line for as long as the shelf is open; once you hide the shelf, what was removed is gone from Stash.

Settings let you change the shortcut, open Stash at login, choose when the shelf clears itself, and choose the language. If a new clearing time would remove something right away, Stash asks first.

## Your files are safe

The rule Stash is built around: adding something to the shelf never moves or changes the original.

- **Files and folders are references.** Stash stores a bookmark to the file, not the file. Removing a row or clearing the shelf only removes the bookmark.
- **Read-only by design.** Stash runs in the App Sandbox and asks macOS only for read access to what you drop on it. The system itself prevents Stash from changing, moving or deleting your files.
- **Dragging out hands over a copy.** Stash never offers "move" when you drag a row out, so no app, Finder included, can take a drag from Stash as permission to move the original. To move a file, move it in Finder.
- **Nothing leaves your Mac.** Stash has no permission to use the network.
- **Nothing is read or indexed.** Stash handles only what you drag onto it. Thumbnails are made by macOS, the same way Finder shows them.

### References and copies

Some things you drag have no lasting file of their own: an image on a web page, an attachment in an email, a file in a temporary folder. Stash keeps those as copies in its own folder, and marks them "copy in Stash". A copy is deleted when you remove it and then hide the shelf.

Links and text are stored in the list itself.

Everything is kept in

```
~/Library/Containers/com.freberdev.stash/Data/Library/Application Support/Stash/
```

`items.json` is the list, with the bookmarks, links and text. `Copies/` holds the copies. The folder is readable only by your user account.

## What drag and drop can and cannot do

Every app describes what it lets you drag in its own way, so some things are worth knowing.

**Dragging in**

- Files and folders from Finder, and from any app that drags real files, become references.
- A file in a temporary folder or a cache becomes a copy instead, because such a file is cleaned away sooner or later. A screenshot dragged from its floating thumbnail is one example.
- A link from a browser's address bar or page becomes a link, with the page title when the browser provides it.
- Selected text becomes text. Text that is nothing but a web address becomes a link.
- An image dragged from a web page becomes a copy of the image. If the image is itself a link, you get the image, not the link.
- Attachments and other files that an app only promises to deliver, from Mail or Photos for example, become copies once the app has written them.
- If an app offers nothing Stash can keep, the pointer shows no green plus and the drop bounces back.
- Stash never accepts a drag as a move. If an app only allows moving, the drop is refused. Some web pages drag their own items that way.
- The same file, link or text dropped twice is not added twice. It moves to the top.

**Dragging out**

- Files are handed over as files, links as links with their title, text as text.
- A file that cannot be found cannot be dragged out.
- What the receiving app does with a drop is up to that app. Text dropped on Finder becomes a clipping file, for instance.

**Files that move or disappear**

- A file that is renamed or moved on the same disk is followed, and the row shows its new name.
- A file that is deleted, put in the Trash, or moved to another disk is shown as "Original not found". The row can be removed; if the file comes back, so does the row.
- A file on a disk that is not connected is shown as not found until the disk is back. Stash never mounts a disk or a network share to look for a file.

**Limits in this version**

- New items go on top. The order cannot be changed.
- No folders, tags or several shelves.
- Clearing by age counts from when the item was added, not from when it was last used.
- No sync between Macs.

## Building

Stash is a Swift package with no dependencies. You need Xcode 26 or later.

```bash
scripts/test.sh
```

```bash
scripts/build-app.sh --install
```

The script builds `build/Stash.app`, signs it with the sandbox entitlements in `Resources/Stash.entitlements` and, with `--install`, copies it to `/Applications`. Without `--install` it only builds.

"Open at login" turns itself on the first time Stash runs from `/Applications`. You can turn it off in Settings.

### Signing

`scripts/build-app.sh` signs with the identity in the environment variable `STASH_SIGN_IDENTITY`, or else the first line of a file named `.signing-identity` in the project folder. With neither, the app is signed ad hoc, which works but makes macOS treat every build as a new app.

```bash
security find-identity -v -p codesigning
```

lists the identities on your Mac. `.signing-identity` is ignored by git.

### A disk image for others

```bash
scripts/build-dmg.sh
```

builds a universal app (Apple silicon and Intel), signs it with a Developer ID certificate, and produces `build/Stash-<version>.dmg`, notarized by Apple.

- The certificate comes from `STASH_RELEASE_IDENTITY` or the first line of `.release-identity`.
- The notarization credentials come from a keychain profile named in `STASH_NOTARY_PROFILE` or the first line of `.notary-profile`. Create the profile once with `xcrun notarytool store-credentials`.

Both files are ignored by git. Without a notary profile the image is signed but not notarized.

### Development options

Three command-line options help when working on Stash:

```bash
open build/Stash.app --args -dataFolder StashDev -showPanel YES -appearance dark
```

`-dataFolder` keeps the shelf in another folder next to the real one, `-showPanel YES` opens the shelf at launch, and `-appearance` (`dark` or `light`) overrides the system setting. `-AppleLanguages "(en)"` or `"(sv)"` starts the app in that language.

### Layout

- `Sources/StashCore` holds the logic: the items, the list on disk, bookmarks, what a drop contains, the key table and the settings. It is covered by the tests in `Tests/StashCoreTests`.
- `Sources/Stash` is the app: the floating panel, the list, the menu bar item, the global shortcut and the settings window.
- `Resources` holds `Info.plist`, the entitlements, the icon and the English and Swedish strings.
- `scripts/make-icon.swift` draws the icon: `swift scripts/make-icon.swift`.

## License

MIT. See [LICENSE](LICENSE).
