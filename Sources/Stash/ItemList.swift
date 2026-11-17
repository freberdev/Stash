import AppKit
import StashCore
import SwiftUI

/// The list of items. A table view from AppKit: it brings selection, keyboard navigation,
/// accessibility and, above all, dependable dragging of one or several rows out to other apps.
struct ItemList: NSViewRepresentable {
    let model: AppModel
    let items: [StashItem]
    let missing: Set<UUID>

    func makeCoordinator() -> ItemListController {
        ItemListController(model: model)
    }

    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.scrollView
    }

    func updateNSView(_ view: NSScrollView, context: Context) {
        context.coordinator.show(items, missing: missing)
    }
}

/// A table view that asks for a context menu for the row under the pointer.
final class ShelfTableView: NSTableView {
    var menuForRow: ((Int) -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let row = row(at: convert(event.locationInWindow, from: nil))
        guard row >= 0 else { return nil }
        // A right-click on a row outside the selection acts on that row alone, as in Finder.
        if !selectedRowIndexes.contains(row) {
            selectRowIndexes([row], byExtendingSelection: false)
        }
        return menuForRow?(row)
    }
}

@MainActor
final class ItemListController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let scrollView = NSScrollView()
    private let tableView = ShelfTableView()
    private let model: AppModel
    private let images = ItemImages()

    private var items: [StashItem] = []
    private var missing: Set<UUID> = []
    private var draggedIDs: Set<UUID> = []
    private var isRestoringSelection = false

    private static let cellID = NSUserInterfaceItemIdentifier("item")

    init(model: AppModel) {
        self.model = model
        super.init()

        let column = NSTableColumn(identifier: Self.cellID)
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .inset
        tableView.rowHeight = 46
        tableView.backgroundColor = .clear
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(openClickedRow)
        tableView.setAccessibilityLabel(L("list.label"))
        tableView.menuForRow = { [weak self] _ in self?.contextMenu() }

        // Dragging out hands over a copy. "Move" is never offered, so no app, Finder included,
        // can take a drag from Stash as permission to move the original.
        tableView.setDraggingSourceOperationMask(.copy, forLocal: false)
        tableView.setDraggingSourceOperationMask([], forLocal: true)

        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        model.list = self
    }

    /// Shows a new version of the list, keeping the selection where the items are still there.
    func show(_ newItems: [StashItem], missing newMissing: Set<UUID>) {
        guard newItems != items || newMissing != missing else { return }
        items = newItems
        missing = newMissing
        images.forget(except: Set(newItems.map(\.id)))

        isRestoringSelection = true
        tableView.reloadData()
        model.selection.formIntersection(newItems.map(\.id))
        let rows = IndexSet(newItems.indices.filter { model.selection.contains(newItems[$0].id) })
        tableView.selectRowIndexes(rows, byExtendingSelection: false)
        isRestoringSelection = false
    }

    func takeFocus() {
        // The table may not be in the window yet when the panel has only just been shown.
        Task { [tableView] in
            tableView.window?.makeFirstResponder(tableView)
        }
    }

    func selectAll() {
        tableView.selectAll(nil)
    }

    func scrollToTop() {
        Task { [tableView] in
            if tableView.numberOfRows > 0 { tableView.scrollRowToVisible(0) }
        }
    }

    // MARK: Rows

    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: Self.cellID, owner: nil) as? ItemCellView ?? {
            let cell = ItemCellView()
            cell.identifier = Self.cellID
            return cell
        }()
        let item = items[row]
        let isMissing = missing.contains(item.id)
        let url = model.store.fileURL(for: item)
        let icon = images.icon(for: item, at: url) { [weak self] in self?.reloadIcon(of: item.id) }
        cell.show(ItemDescription(item, isMissing: isMissing), icon: icon)
        cell.onRemove = { [weak self] in self?.model.remove([item.id]) }
        return cell
    }

    /// Called when a thumbnail has arrived for a row that was first shown with a plain icon.
    private func reloadIcon(of id: UUID) {
        guard let row = items.firstIndex(where: { $0.id == id }) else { return }
        tableView.reloadData(forRowIndexes: [row], columnIndexes: [0])
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isRestoringSelection else { return }
        model.selection = Set(tableView.selectedRowIndexes.filter { $0 < items.count }.map { items[$0].id })
    }

    // MARK: Dragging out

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        model.pasteboardWriter(for: items[row])
    }

    func tableView(
        _ tableView: NSTableView, draggingSession session: NSDraggingSession,
        willBeginAt screenPoint: NSPoint, forRowIndexes rowIndexes: IndexSet
    ) {
        draggedIDs = Set(rowIndexes.filter { $0 < items.count }.map { items[$0].id })
    }

    func tableView(
        _ tableView: NSTableView, draggingSession session: NSDraggingSession,
        endedAt screenPoint: NSPoint, operation: NSDragOperation
    ) {
        if operation != [] { model.store.markUsed(draggedIDs) }
        draggedIDs = []
    }

    // MARK: Double-click and context menu

    @objc private func openClickedRow() {
        let row = tableView.clickedRow
        guard row >= 0, row < items.count else { return }
        model.open(items[row])
    }

    private func contextMenu() -> NSMenu {
        let selected = items.filter { model.selection.contains($0.id) }
        let hasFile = selected.contains { model.store.fileURL(for: $0) != nil }
        let canHandOver = selected.contains { model.pasteboardWriter(for: $0) != nil }

        let menu = NSMenu()
        menu.autoenablesItems = false
        func add(_ title: String, _ action: Selector, enabled: Bool = true) {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
            entry.target = self
            entry.isEnabled = enabled
            menu.addItem(entry)
        }
        add(L("row.open"), #selector(openFromMenu), enabled: canHandOver)
        add(L("row.reveal"), #selector(revealFromMenu), enabled: hasFile)
        add(L("row.copy"), #selector(copyFromMenu), enabled: canHandOver)
        menu.addItem(.separator())
        add(L("row.remove"), #selector(removeFromMenu))
        return menu
    }

    @objc private func openFromMenu() { model.openSelected() }
    @objc private func revealFromMenu() { model.revealSelected() }
    @objc private func copyFromMenu() { model.copySelected() }
    @objc private func removeFromMenu() { model.removeSelected() }
}
