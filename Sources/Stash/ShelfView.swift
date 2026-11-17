import StashCore
import SwiftUI

/// The content of the shelf: the items, or an invitation to drop some, and one quiet line underneath.
struct ShelfView: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if model.store.items.isEmpty {
                EmptyShelf(shortcut: model.shortcutDisplay, isTargeted: model.isDropTargeted)
            } else {
                ItemList(model: model, items: model.store.items, missing: model.store.missing)
            }
            ShelfFooter(model: model)
        }
        .overlay {
            if model.isDropTargeted, !model.store.items.isEmpty {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .padding(5)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// What the shelf shows when there is nothing on it.
private struct EmptyShelf: View {
    let shortcut: String
    let isTargeted: Bool

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(isTargeted ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                .accessibilityHidden(true)
            Text(L("empty.title"))
                .font(.callout)
                .multilineTextAlignment(.center)
            Text(L("empty.hint", shortcut))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isTargeted ? AnyShapeStyle(Color.accentColor.opacity(0.10)) : AnyShapeStyle(.clear))
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isTargeted ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
    }
}

/// The bottom line: how much is on the shelf or what just happened, and the few controls.
private struct ShelfFooter: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            status
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            if model.notice?.offersUndo == true {
                Button(L("footer.undo")) { model.undo() }
                    .help(L("footer.undo.help"))
            } else if !model.store.items.isEmpty {
                Button(L("footer.clear")) { model.clear() }
                    .help(L("footer.clear.help"))
            }

            Menu {
                Button(L("menu.settings")) { model.openSettings() }
                Divider()
                Button(L("menu.quit")) { NSApplication.shared.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(L("footer.more"))
        }
        .font(.caption)
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    @ViewBuilder private var status: some View {
        if let notice = model.notice {
            Text(notice.text)
                .foregroundStyle(notice.isProblem ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
        } else if model.store.saveFailed {
            Text(L("footer.saveFailed"))
                .foregroundStyle(.red)
        } else if !model.store.items.isEmpty {
            Text(L(count: model.store.items.count, one: "footer.count.one", many: "footer.count.many"))
                .foregroundStyle(.tertiary)
        }
    }
}
