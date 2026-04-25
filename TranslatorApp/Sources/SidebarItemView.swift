import AppKit

/// Single row in the Settings sidebar — SF Symbol on the left, label on
/// the right, rounded background highlight when selected. Clickable.
final class SidebarItemView: NSView {

    let sectionID: String
    var onClick: (() -> Void)?

    var isSelected: Bool = false {
        didSet { needsDisplay = true; updateAppearance() }
    }

    private let iconView = NSImageView()
    private let label    = NSTextField(labelWithString: "")

    init(identifier: String, symbolName: String, title: String) {
        self.sectionID = identifier
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 7

        let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)?
            .withSymbolConfiguration(cfg)
        iconView.translatesAutoresizingMaskIntoConstraints = false

        label.stringValue = title
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13, weight: .regular)

        let stack = NSStackView(views: [iconView, label])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),

            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            heightAnchor.constraint(equalToConstant: 30),
        ])

        updateAppearance()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func updateAppearance() {
        layer?.backgroundColor = isSelected
            ? NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor
            : NSColor.clear.cgColor
        label.font = .systemFont(
            ofSize: 13,
            weight: isSelected ? .semibold : .regular
        )
        label.textColor = isSelected
            ? .controlAccentColor
            : .labelColor
        iconView.contentTintColor = isSelected
            ? .controlAccentColor
            : .secondaryLabelColor
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

/// NSView that flips its coordinate system so subviews placed at top
/// y=0 stay pinned to the top in an NSScrollView (which otherwise
/// treats y=0 as the bottom). Used inside the settings scroll view.
final class FlippedContainerView: NSView {
    override var isFlipped: Bool { true }
}

/// Lightweight rounded "card" container — used to wrap individual
/// settings sections so the right pane reads as grouped surfaces
/// instead of a flat form.
final class CardView: NSView {

    init(content: NSView, padding: CGFloat = 18) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.backgroundColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 1, alpha: 0.06)
                : NSColor.white.withAlphaComponent(0.65)
        }.cgColor
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.cgColor

        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            content.topAnchor.constraint(equalTo: topAnchor, constant: padding),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -padding),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}
