import AppKit
import Observation

/// The item in the menu bar. A click shows or hides the shelf, a right-click opens a small
/// menu, and things can be dropped straight onto the icon.
@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
        super.init()
        guard let button = item.button else { return }

        button.target = self
        button.action = #selector(clicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.setAccessibilityLabel("Stash")
        button.toolTip = L("status.help", model.shortcutDisplay)

        let dropView = DropView(frame: button.bounds)
        dropView.autoresizingMask = [.width, .height]
        dropView.passesClicksThrough = true
        dropView.onTargeted = { [weak button] targeted in button?.highlight(targeted) }
        dropView.onDrop = { [weak self] pasteboard in
            guard let self else { return false }
            let accepted = self.model.acceptDrop(pasteboard)
            // Show what just landed, without taking the keyboard from the app the user is in.
            self.model.showPanel(takingFocus: false)
            return accepted
        }
        button.addSubview(dropView)

        followShelf()
    }

    /// A full tray when there is something on the shelf, an empty one otherwise.
    private func followShelf() {
        withObservationTracking {
            let name = model.store.items.isEmpty ? "tray" : "tray.full"
            item.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "Stash")
            item.button?.toolTip = L("status.help", model.shortcutDisplay)
        } onChange: { [weak self] in
            Task { @MainActor in self?.followShelf() }
        }
    }

    @objc private func clicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            model.togglePanel()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector, enabled: Bool = true) {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
            entry.target = self
            entry.isEnabled = enabled
            menu.addItem(entry)
        }
        menu.autoenablesItems = false
        let shortcut = model.shortcutDisplay
        add(model.isPanelVisible ? L("menu.hide", shortcut) : L("menu.show", shortcut), #selector(toggle))
        add(L("menu.clear"), #selector(clear), enabled: !model.store.items.isEmpty)
        menu.addItem(.separator())
        add(L("menu.settings"), #selector(settings))
        menu.addItem(.separator())
        add(L("menu.quit"), #selector(quit))

        // With a menu attached, a click opens it. It is attached only for this one click.
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func toggle() { model.togglePanel() }
    @objc private func settings() { model.openSettings() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func clear() {
        model.clear()
        // The offer to undo is shown in the shelf.
        model.showPanel(takingFocus: false)
    }
}
