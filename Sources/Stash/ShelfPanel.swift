import AppKit
import StashCore
import SwiftUI

/// The floating shelf. It stays above other windows and takes clicks, drops and keys without
/// making Stash the active app, so the app the user is working in stays in front.
final class ShelfPanel: NSPanel {
    /// Sees every key press first. Returns true when the key has been dealt with.
    var keyHandler: (@MainActor (NSEvent) -> Bool)?

    init(size: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        title = "Stash"
        titlebarAppearsTransparent = true
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        minSize = NSSize(width: 240, height: 200)
        for button in [NSWindow.ButtonType.miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Command shortcuts arrive here before they reach the menu bar…
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown, keyHandler?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    // …and every other key arrives here before it reaches the list.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, keyHandler?(event) == true { return }
        super.sendEvent(event)
    }
}

/// Creates the panel once and shows, hides and places it.
@MainActor
final class ShelfPanelController: NSObject, NSWindowDelegate {
    static let defaultSize = NSSize(width: 300, height: 420)
    private static let frameKey = "shelfPanelFrame"

    let panel = ShelfPanel(size: ShelfPanelController.defaultSize)
    var onDropTargeted: ((Bool) -> Void)?
    var onDrop: ((NSPasteboard) -> Bool)?
    /// Called when the user closes the panel with its close button.
    var onClosed: (() -> Void)?

    private let defaults: UserDefaults
    private var isPlacing = false

    init(rootView: some View, defaults: UserDefaults = .standard, keyHandler: @escaping @MainActor (NSEvent) -> Bool) {
        self.defaults = defaults
        super.init()

        // The whole panel is the drop target, not just the list.
        let dropView = DropView()
        dropView.onTargeted = { [weak self] targeted in self?.onDropTargeted?(targeted) }
        dropView.onDrop = { [weak self] pasteboard in self?.onDrop?(pasteboard) ?? false }

        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.frame = dropView.bounds
        background.autoresizingMask = [.width, .height]
        dropView.addSubview(background)

        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = dropView.bounds
        hosting.autoresizingMask = [.width, .height]
        dropView.addSubview(hosting)

        panel.contentView = dropView
        panel.keyHandler = keyHandler
        panel.delegate = self
    }

    var isVisible: Bool { panel.isVisible }
    var hasFocus: Bool { panel.isVisible && panel.isKeyWindow }

    /// Shows the panel. Without focus it appears without taking the keyboard from the app in front.
    func show(takingFocus: Bool) {
        if !panel.isVisible { place() }
        if takingFocus {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        panel.orderOut(nil)
    }

    // MARK: Placement

    /// Where the user last left the panel, or the right edge of the screen with the pointer.
    private func place() {
        isPlacing = true
        defer { isPlacing = false }

        if let saved = defaults.string(forKey: Self.frameKey) {
            let frame = NSRectFromString(saved)
            if frame.width >= panel.minSize.width, frame.height >= panel.minSize.height,
               NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
                panel.setFrame(frame, display: false)
                return
            }
        }
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = Self.defaultSize
        let origin = NSPoint(x: visible.maxX - size.width - 16, y: visible.midY - size.height / 2)
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
    }

    private func rememberFrame() {
        guard !isPlacing, panel.isVisible else { return }
        defaults.set(NSStringFromRect(panel.frame), forKey: Self.frameKey)
    }

    func windowDidMove(_ notification: Notification) { rememberFrame() }
    func windowDidEndLiveResize(_ notification: Notification) { rememberFrame() }
    func windowWillClose(_ notification: Notification) { onClosed?() }
}

/// A view that accepts files, links, text and images dragged in from other apps.
final class DropView: NSView {
    var onTargeted: ((Bool) -> Void)?
    var onDrop: ((NSPasteboard) -> Bool)?
    /// When true, clicks fall through to the view underneath. Drops are still taken.
    var passesClicksThrough = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes(DropReader.acceptedTypes)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? {
        passesClicksThrough ? nil : super.hitTest(point)
    }

    /// Stash only ever takes a copy or a reference. It never answers "move", which would
    /// tell the source app that the original is now Stash's to keep.
    private func operation(for sender: any NSDraggingInfo) -> NSDragOperation {
        // Something dragged from the shelf itself is already here.
        guard sender.draggingSource == nil else { return [] }
        let offered = sender.draggingSourceOperationMask
        if offered.contains(.copy) { return .copy }
        if offered.contains(.link) { return .link }
        if offered.contains(.generic) { return .generic }
        return []
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let operation = operation(for: sender)
        onTargeted?(operation != [])
        return operation
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        operation(for: sender)
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        onTargeted?(false)
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        onTargeted?(false)
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        operation(for: sender) != []
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        onDrop?(sender.draggingPasteboard) ?? false
    }
}
