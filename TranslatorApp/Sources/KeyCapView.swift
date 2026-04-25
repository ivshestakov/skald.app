import AppKit

/// Renders a single keyboard key as a small physical-looking "keycap":
/// rounded rect, soft border, monospace label inside. Used in the
/// Settings → Shortcuts tab so the key combinations look like keys
/// instead of inline text.
final class KeyCapView: NSView {

    private let label = NSTextField(labelWithString: "")

    init(_ key: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.borderWidth = 0.75

        label.translatesAutoresizingMaskIntoConstraints = false
        label.stringValue = key
        label.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        label.alignment = .center
        label.textColor = .labelColor
        addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 24),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 24),
            // Make the cap a touch wider than tall so single glyphs
            // don't look pinched.
            widthAnchor.constraint(greaterThanOrEqualTo: label.widthAnchor, constant: 14),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        // On light Settings bg the previous semantic colours rendered
        // dark gray and disappeared into the card. Use explicit values:
        // near-white in light mode, soft white in dark mode.
        layer?.backgroundColor = (isDark
            ? NSColor(white: 1, alpha: 0.18)
            : NSColor(white: 1, alpha: 0.95)
        ).cgColor
        layer?.borderColor = (isDark
            ? NSColor(white: 1, alpha: 0.32)
            : NSColor(white: 0, alpha: 0.20)
        ).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
