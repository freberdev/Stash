import AppKit

/// One row: an icon or thumbnail, a name, a line saying what and where it is, and a
/// button that takes the item off the shelf.
final class ItemCellView: NSTableCellView {
    var onRemove: (() -> Void)?

    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(labelWithString: "")
    private let removeButton = NSButton()
    private var isHovered = false

    override init(frame: NSRect) {
        super.init(frame: frame)

        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.setAccessibilityElement(false)

        title.font = .systemFont(ofSize: 13)
        title.lineBreakMode = .byTruncatingMiddle
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.lineBreakMode = .byTruncatingTail
        subtitle.textColor = .secondaryLabelColor
        for label in [title, subtitle] {
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }

        removeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: nil)
        removeButton.isBordered = false
        removeButton.imagePosition = .imageOnly
        removeButton.contentTintColor = .tertiaryLabelColor
        removeButton.target = self
        removeButton.action = #selector(removeClicked)
        removeButton.isHidden = true

        let text = NSStackView(views: [title, subtitle])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1

        for view in [icon, text, removeButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 32),
            icon.heightAnchor.constraint(equalToConstant: 32),
            text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 9),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
            text.trailingAnchor.constraint(equalTo: removeButton.leadingAnchor, constant: -6),
            removeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            removeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            removeButton.widthAnchor.constraint(equalToConstant: 18),
            removeButton.heightAnchor.constraint(equalToConstant: 18),
        ])
        textField = title
        imageView = icon
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(_ description: ItemDescription, icon image: ItemIcon) {
        title.stringValue = description.title
        subtitle.stringValue = description.subtitle
        subtitle.textColor = description.isMissing ? .systemOrange : .secondaryLabelColor
        toolTip = description.toolTip

        icon.image = image.image
        icon.contentTintColor = image.isSymbol ? .secondaryLabelColor : nil
        icon.alphaValue = description.isMissing ? 0.45 : 1
        title.alphaValue = description.isMissing ? 0.6 : 1

        removeButton.toolTip = L("row.remove")
        removeButton.setAccessibilityLabel(L("row.remove.label", description.title))
        setAccessibilityLabel(description.title + ", " + description.subtitle)
        updateRemoveButton()
    }

    @objc private func removeClicked() {
        onRemove?()
    }

    // MARK: The remove button appears under the pointer

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateRemoveButton()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateRemoveButton()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        isHovered = false
        onRemove = nil
    }

    private func updateRemoveButton() {
        removeButton.isHidden = !isHovered
    }
}
