import AppKit
import SwiftUI

/// The settings window. Stash has no Dock icon, so the window is created and brought forward by hand;
/// SwiftUI's own Settings scene tends to open behind other apps in that situation.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    /// Called when the window closes or stops being the key window.
    var onInactive: (() -> Void)?

    private var window: NSWindow?
    private let makeContent: () -> AnyView

    init(content: @escaping () -> some View) {
        makeContent = { AnyView(content()) }
    }

    func show() {
        if window == nil {
            let window = SettingsWindow(contentViewController: NSHostingController(rootView: makeContent()))
            window.title = L("settings.title")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        // Stash is not the active app when this is called from the shelf or the menu bar.
        NSApp.activateInsistently()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowDidResignKey(_ notification: Notification) { onInactive?() }
    func windowWillClose(_ notification: Notification) { onInactive?() }
}

/// Stash has no menu bar of its own, so ⌘W has to be handled by the window.
private final class SettingsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.type == .keyDown, flags == .command, event.charactersIgnoringModifiers?.lowercased() == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

extension NSApplication {
    /// Makes Stash the active app even when another app is in front.
    ///
    /// The cooperative `activate()` is only a request, and it is ignored when Stash is not already
    /// active, which is always the case for an app that lives in the menu bar.
    func activateInsistently() {
        (self as InsistentActivation).activate(ignoringOtherApps: true)
    }
}

/// Reaches `activate(ignoringOtherApps:)` without a deprecation warning at the call site.
@MainActor
private protocol InsistentActivation {
    func activate(ignoringOtherApps flag: Bool)
}

extension NSApplication: InsistentActivation {}
