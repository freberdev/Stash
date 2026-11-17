import AppKit
import Observation
import StashCore
import SwiftUI

/// Ties the shelf, its panel, the menu bar item and the global shortcut together.
@MainActor @Observable
final class AppModel {
    /// A short message in the panel's bottom line.
    struct Notice: Equatable {
        let id = UUID()
        var text: String
        var offersUndo = false
        var isProblem = false
    }

    let store: ItemStore

    private(set) var notice: Notice?
    /// True while something that can be dropped is held over the panel or the menu bar item.
    var isDropTargeted = false

    /// The global shortcut that opens Stash.
    private(set) var shortcut: Shortcut
    /// Something the user should know about the shortcut they just chose, or nil.
    var shortcutMessage: String?
    /// True while the settings window is waiting for the user to press a new shortcut.
    private(set) var isRecordingShortcut = false
    private(set) var retention: Retention
    /// The language chosen for the app. It is read by macOS when the app starts.
    private(set) var language: AppLanguage

    /// The rows selected in the list.
    @ObservationIgnored var selection: Set<UUID> = []
    @ObservationIgnored weak var list: ItemListController?

    @ObservationIgnored private let preferences = Preferences()
    @ObservationIgnored private let hotKey = HotKey()
    @ObservationIgnored private var panel: ShelfPanelController?
    @ObservationIgnored private var statusItem: StatusItemController?
    @ObservationIgnored private var settingsWindow: SettingsWindowController?
    @ObservationIgnored private var shortcutMonitor: Any?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private var housekeeping: Timer?

    init() {
        // "-dataFolder <name>" on the command line keeps the shelf in another folder, for development.
        let folder = UserDefaults.standard.string(forKey: "dataFolder") ?? "Stash"
        store = ItemStore(directory: ItemStore.defaultDirectory(named: folder))
        shortcut = preferences.shortcut
        retention = preferences.retention
        language = AppLanguage.chosen(domain: Bundle.main.bundleIdentifier ?? "")
    }

    /// Called once the app has launched: builds the panel and claims the shortcut.
    func start() {
        store.load()
        store.removeExpired(retention)

        let controller = ShelfPanelController(rootView: ShelfView(model: self)) { [weak self] event in
            self?.handleKey(event) ?? false
        }
        controller.onDropTargeted = { [weak self] targeted in self?.isDropTargeted = targeted }
        controller.onDrop = { [weak self] pasteboard in self?.acceptDrop(pasteboard) ?? false }
        controller.onClosed = { [weak self] in self?.panelDidClose() }
        panel = controller

        statusItem = StatusItemController(model: self)

        hotKey.onPressed = { [weak self] in self?.hotKeyPressed() }
        resumeHotKey()

        let settings = SettingsWindowController { [unowned self] in SettingsView(model: self) }
        settings.onInactive = { [weak self] in self?.stopRecordingShortcut() }
        settingsWindow = settings

        housekeeping = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.keepHouse() }
        }

        enableLoginItemOnce()
        if preferences.reopensSettings {
            // The app has just restarted itself to change language. Go back to where the user was.
            preferences.reopensSettings = false
            openSettings()
        }
        // "-showPanel YES" on the command line opens the shelf at launch, for development.
        if !preferences.hasShownWelcome || UserDefaults.standard.bool(forKey: "showPanel") {
            preferences.hasShownWelcome = true
            showPanel()
        }
    }

    func willQuit() {
        store.forgetRemoved()
    }

    /// Stash is of little use if it is not running, so "open at login" is turned on the first
    /// time it runs from the Applications folder. Only ever once: after that the choice
    /// belongs to the user.
    private func enableLoginItemOnce() {
        guard LoginItem.isInstalled, !preferences.didAutoEnableLoginItem else { return }
        preferences.didAutoEnableLoginItem = true
        try? LoginItem.setEnabled(true)
    }

    /// Runs every few seconds: clears what has been on the shelf too long, and while the
    /// shelf is on screen checks that the files are still where they were.
    private func keepHouse() {
        store.removeExpired(retention)
        if panel?.isVisible == true { store.refresh() }
    }

    // MARK: Opening and closing

    var isPanelVisible: Bool { panel?.isVisible ?? false }

    /// Closed: open. Open with focus: close. Open without focus: take focus.
    func hotKeyPressed() {
        guard let panel else { return }
        if !panel.isVisible {
            showPanel()
        } else if panel.hasFocus {
            closePanel()
        } else {
            panel.show(takingFocus: true)
            list?.takeFocus()
        }
    }

    /// A click on the menu bar item shows or hides the shelf.
    func togglePanel() {
        if isPanelVisible { closePanel() } else { showPanel() }
    }

    func showPanel(takingFocus: Bool = true) {
        store.refresh()
        panel?.show(takingFocus: takingFocus)
        if takingFocus { list?.takeFocus() }
    }

    func closePanel() {
        panel?.hide()
        panelDidClose()
    }

    /// Removed items can be brought back for as long as the shelf stays open.
    private func panelDidClose() {
        store.forgetRemoved()
        setNotice(nil)
        isDropTargeted = false
    }

    // MARK: Taking things in

    /// Puts what was dropped on the shelf. Must be called while the drop is still in progress:
    /// that is when the system lets the app see the dropped files.
    @discardableResult
    func acceptDrop(_ pasteboard: NSPasteboard) -> Bool {
        isDropTargeted = false
        switch DropReader.read(pasteboard) {
        case .files(let urls):
            report(store.addFiles(urls))
            return true
        case .promisedFiles:
            receivePromisedFiles(from: pasteboard)
            return true
        case .pieces(let pieces):
            // Added last to first, so the first piece ends up on top.
            let outcome = pieces.reversed().reduce(AddOutcome()) { $0 + add($1) }
            report(outcome)
            return outcome.added + outcome.alreadyThere > 0
        case .nothing:
            setNotice(Notice(text: L("drop.unsupported"), isProblem: true))
            return false
        }
    }

    private func add(_ piece: DropPiece) -> AddOutcome {
        switch piece {
        case .link(let url, let title):
            return store.addLink(url, title: title)
        case .text(let text):
            return store.addText(text)
        case .image(let data, let fileExtension):
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
            let name = L("item.image.name") + " " + formatter.string(from: Date()) + "." + fileExtension
            return store.addImage(data, fileName: name)
        }
    }

    /// Asks the source app to write the files it promised into Stash's own folder.
    /// They arrive a moment later, one by one.
    private func receivePromisedFiles(from pasteboard: NSPasteboard) {
        for receiver in DropReader.promiseReceivers(on: pasteboard) {
            guard let folder = try? store.makeCopyDirectory() else {
                report(AddOutcome(failed: 1))
                continue
            }
            receiver.receivePromisedFiles(atDestination: folder, options: [:], operationQueue: .main) {
                [weak self] url, error in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.report(error == nil ? self.store.addCopy(at: url) : AddOutcome(failed: 1))
                }
            }
        }
    }

    private func report(_ outcome: AddOutcome) {
        if outcome.added > 0 {
            selection = []
            list?.scrollToTop()
        }
        if outcome.failed > 0 {
            let text = outcome.added > 0
                ? L("drop.partlyFailed", outcome.added, outcome.failed)
                : L("drop.failed")
            setNotice(Notice(text: text, isProblem: true))
        } else if outcome.added == 0, outcome.alreadyThere > 0 {
            setNotice(Notice(text: L("drop.alreadyThere")))
        } else if outcome.added > 0 {
            setNotice(nil)
        }
    }

    // MARK: Handing things out

    /// What an item puts on the pasteboard when it is dragged out or copied.
    /// Nil for a file that cannot be found: there is nothing to hand over.
    func pasteboardWriter(for item: StashItem) -> (any NSPasteboardWriting)? {
        switch item.content {
        case .reference, .copy:
            return store.fileURL(for: item).map { $0 as NSURL }
        case .link(let url):
            let entry = NSPasteboardItem()
            entry.setString(url.absoluteString, forType: .URL)
            entry.setString(item.name, forType: NSPasteboard.PasteboardType("public.url-name"))
            entry.setString(url.absoluteString, forType: .string)
            return entry
        case .text(let text):
            let entry = NSPasteboardItem()
            entry.setString(text, forType: .string)
            return entry
        }
    }

    private var selectedItems: [StashItem] {
        store.items.filter { selection.contains($0.id) }
    }

    func open(_ item: StashItem) {
        switch item.content {
        case .reference, .copy:
            guard let url = store.fileURL(for: item) else {
                NSSound.beep()
                return
            }
            NSWorkspace.shared.open(url)
        case .link(let url):
            NSWorkspace.shared.open(url)
        case .text:
            // There is nowhere to open a piece of text. Putting it on the clipboard is the useful thing.
            copy([item])
            return
        }
        store.markUsed([item.id])
    }

    func openSelected() {
        selectedItems.forEach(open)
    }

    func revealSelected() {
        let urls = selectedItems.compactMap { store.fileURL(for: $0) }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func copySelected() {
        copy(selectedItems)
    }

    private func copy(_ items: [StashItem]) {
        let writers = items.compactMap { item in pasteboardWriter(for: item) }
        guard !writers.isEmpty else {
            if !items.isEmpty { NSSound.beep() }
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(writers)
        store.markUsed(Set(items.map(\.id)))
        setNotice(Notice(text: L("notice.copied")))
    }

    // MARK: Removing

    func remove(_ ids: Set<UUID>) {
        let count = store.remove(ids)
        guard count > 0 else { return }
        selection.subtract(ids)
        setNotice(Notice(
            text: L(count: count, one: "notice.removed.one", many: "notice.removed.many"), offersUndo: true))
    }

    func removeSelected() {
        remove(selection)
    }

    func clear() {
        let count = store.clear()
        guard count > 0 else { return }
        selection = []
        setNotice(Notice(text: L("notice.cleared"), offersUndo: true))
    }

    func undo() {
        guard store.undo() > 0 else { return }
        setNotice(nil)
    }

    private func setNotice(_ new: Notice?) {
        noticeTask?.cancel()
        notice = new
        guard let new else { return }
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(new.offersUndo ? 8 : 4))
            guard !Task.isCancelled, self?.notice?.id == new.id else { return }
            self?.notice = nil
        }
    }

    // MARK: Settings

    func openSettings() {
        settingsWindow?.show()
    }

    /// Changes when the shelf clears itself. If that would clear something right away, the
    /// user is asked first: clearing by age cannot be undone, and it deletes copies.
    func setRetention(_ new: Retention) {
        let count = store.expiredCount(new)
        if count > 0 {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L(
                count: count, one: "settings.retention.confirm.one", many: "settings.retention.confirm.many")
            alert.informativeText = L("settings.retention.confirm.message")
            alert.addButton(withTitle: L("settings.retention.confirm.clear"))
            alert.addButton(withTitle: L("settings.retention.confirm.cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        retention = new
        preferences.retention = new
        store.removeExpired(new)
    }

    /// Changes the language of the app. macOS decides the language of an app when it starts,
    /// and that covers the system's own words as well, such as the names of file kinds.
    /// So Stash starts again, which takes a moment and loses nothing.
    func setLanguage(_ new: AppLanguage) {
        guard new != language else { return }
        language = new
        new.store()
        preferences.reopensSettings = true
        restart()
    }

    private func restart() {
        stopRecordingShortcut()
        // The new instance must be able to claim the shortcut, so this one lets go of it first.
        hotKey.unregister()
        store.forgetRemoved()

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) {
            [weak self] _, error in
            let started = error == nil
            Task { @MainActor in
                if started {
                    NSApp.terminate(nil)
                } else {
                    // Could not start again. Carry on; the language changes the next time Stash is opened.
                    self?.preferences.reopensSettings = false
                    self?.resumeHotKey()
                }
            }
        }
    }

    /// The shortcut as the user sees it, for example "⌃⌥S".
    var shortcutDisplay: String {
        shortcut.modifierSymbols + KeyNames.name(for: shortcut.keyCode)
    }

    private func resumeHotKey() {
        hotKey.register(keyCode: shortcut.keyCode, carbonModifiers: shortcut.carbonModifiers)
    }

    /// Waits for the next key combination and makes it the shortcut. Escape cancels.
    func startRecordingShortcut() {
        guard !isRecordingShortcut else { return }
        isRecordingShortcut = true
        shortcutMessage = nil
        // The current shortcut must not fire while the user is choosing a new one.
        hotKey.unregister()
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.recordShortcut(from: event)
            return nil
        }
    }

    /// Ends recording and puts the shortcut back in force. Also called when the settings
    /// window closes or loses focus, so the shortcut can never be left switched off.
    func stopRecordingShortcut() {
        guard isRecordingShortcut else { return }
        isRecordingShortcut = false
        if let shortcutMonitor { NSEvent.removeMonitor(shortcutMonitor) }
        shortcutMonitor = nil
        resumeHotKey()
    }

    private func recordShortcut(from event: NSEvent) {
        let modifiers = KeyModifiers(event.modifierFlags)
        if event.keyCode == 53, modifiers.isEmpty {
            stopRecordingShortcut()
            return
        }
        let candidate = Shortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers)
        guard candidate.isValid else {
            shortcutMessage = L("settings.shortcut.needsModifier")
            return
        }
        stopRecordingShortcut()
        setShortcut(candidate)
    }

    /// Switches to a new shortcut. If the system refuses it, the previous one stays.
    private func setShortcut(_ new: Shortcut) {
        if hotKey.register(keyCode: new.keyCode, carbonModifiers: new.carbonModifiers) {
            shortcut = new
            preferences.shortcut = new
            shortcutMessage = nil
        } else {
            resumeHotKey()
            shortcutMessage = L("settings.shortcut.refused")
        }
    }

    // MARK: Keys

    private func handleKey(_ event: NSEvent) -> Bool {
        guard let command = ShelfKeys.command(for: StashCore.KeyPress(event)) else { return false }
        // A held key is swallowed rather than repeated: a long press must not remove row after row.
        if !event.isARepeat { perform(command) }
        return true
    }

    private func perform(_ command: ShelfCommand) {
        switch command {
        case .close: closePanel()
        case .openSelected: openSelected()
        case .removeSelected: removeSelected()
        case .copySelected: copySelected()
        case .selectAll: list?.selectAll()
        case .undo: undo()
        case .settings: openSettings()
        }
    }
}

extension StashCore.KeyPress {
    /// The key and modifiers of an event, with the character the key types on the current layout.
    init(_ event: NSEvent) {
        // With Command held, most non-Latin layouts report a Latin character in `characters`.
        // Control and Option change `characters` to something else, so the unmodified one is tried too.
        let candidates = [event.characters, event.charactersIgnoringModifiers]
        let character = candidates.compactMap { $0 }.first { text in
            text.unicodeScalars.count == 1 && text.unicodeScalars.allSatisfy { (0x21...0x7E).contains($0.value) }
        }
        self.init(
            keyCode: event.keyCode,
            modifiers: KeyModifiers(event.modifierFlags),
            character: character ?? ShelfKeys.usCharacters[event.keyCode])
    }
}

extension KeyModifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        self = []
        if flags.contains(.command) { insert(.command) }
        if flags.contains(.shift) { insert(.shift) }
        if flags.contains(.option) { insert(.option) }
        if flags.contains(.control) { insert(.control) }
    }
}
