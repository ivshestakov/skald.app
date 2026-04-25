import AppKit

/// A click-to-record shortcut field. Click the box to enter recording
/// mode, then press the new combination. Esc cancels. The combination
/// must include at least one modifier (⌘ ⌥ ⌃ ⇧) — bare keypresses are
/// rejected with a beep so the user can't accidentally bind the panel
/// to a normal letter.
final class ShortcutRecorderView: NSView {

    private(set) var keyCode: Int
    private(set) var modifiers: NSEvent.ModifierFlags
    private(set) var displayChar: String

    /// Fired when the user lands a new valid combo. Persist + re-register.
    var onChange: ((Int, NSEvent.ModifierFlags, String) -> Void)?

    private let stack  = NSStackView()
    private let prompt = NSTextField(labelWithString: "Press shortcut…")

    private var monitor: Any?
    private var recording = false {
        didSet { rebuild(); needsDisplay = true }
    }

    init(keyCode: Int,
         modifiers: NSEvent.ModifierFlags,
         displayChar: String) {
        self.keyCode    = keyCode
        self.modifiers  = modifiers
        self.displayChar = displayChar
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 6

        stack.orientation = .horizontal
        stack.spacing = 4
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        prompt.font = .systemFont(ofSize: 12, weight: .medium)
        prompt.textColor = .secondaryLabelColor
        prompt.alignment = .center

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            heightAnchor.constraint(equalToConstant: 32),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
        ])
        rebuild()
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let m = monitor { NSEvent.removeMonitor(m) }
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        let normalBg = isDark
            ? NSColor(white: 1, alpha: 0.06)
            : NSColor(white: 1, alpha: 0.55)
        let normalBorder = isDark
            ? NSColor(white: 1, alpha: 0.18)
            : NSColor(white: 0, alpha: 0.18)

        layer?.backgroundColor = (recording
            ? NSColor.controlAccentColor.withAlphaComponent(0.18)
            : normalBg
        ).cgColor
        layer?.borderColor = (recording
            ? NSColor.controlAccentColor
            : normalBorder
        ).cgColor
        layer?.borderWidth = recording ? 1.5 : 0.75
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        if !recording { beginRecording() }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    // MARK: rendering

    private func rebuild() {
        for v in stack.arrangedSubviews {
            stack.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
        if recording {
            stack.addArrangedSubview(prompt)
            return
        }
        let mods: [(NSEvent.ModifierFlags, String)] = [
            (.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘"),
        ]
        for (flag, glyph) in mods where modifiers.contains(flag) {
            stack.addArrangedSubview(KeyCapView(glyph))
        }
        stack.addArrangedSubview(KeyCapView(displayChar))
    }

    // MARK: recording

    private func beginRecording() {
        recording = true
        // Local monitor catches all key events while we have focus.
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .flagsChanged]
        ) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    private func endRecording() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        recording = false
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard event.type == .keyDown else { return event }

        // Esc cancels (keyCode 53).
        if event.keyCode == 53 {
            endRecording()
            return nil
        }
        let mods = event.modifierFlags.intersection(
            [.command, .option, .control, .shift]
        )
        // Bare keypresses (no modifier) are rejected.
        guard !mods.isEmpty else {
            NSSound.beep()
            return nil
        }

        let kc = Int(event.keyCode)
        let display: String = {
            if let chars = event.charactersIgnoringModifiers,
               !chars.isEmpty,
               let scalar = chars.unicodeScalars.first,
               scalar.value >= 32 {
                return chars.uppercased()
            }
            return KeyCodeFormatter.keyName(forKeyCode: kc)
        }()

        self.keyCode     = kc
        self.modifiers   = mods
        self.displayChar = display
        onChange?(kc, mods, display)
        endRecording()
        return nil
    }
}

/// Mapping from raw Carbon virtual keycodes to printable glyphs for the
/// keys that don't produce a sensible `charactersIgnoringModifiers`.
enum KeyCodeFormatter {
    static func keyName(forKeyCode keyCode: Int) -> String {
        switch keyCode {
        case 36:  return "↵"     // return
        case 48:  return "⇥"     // tab
        case 49:  return "Space"
        case 51:  return "⌫"     // delete (backspace)
        case 53:  return "⎋"     // escape
        case 117: return "⌦"     // forward delete
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 116: return "⇞"     // page up
        case 121: return "⇟"     // page down
        case 115: return "↖"     // home
        case 119: return "↘"     // end
        case 122: return "F1"
        case 120: return "F2"
        case 99:  return "F3"
        case 118: return "F4"
        case 96:  return "F5"
        case 97:  return "F6"
        case 98:  return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        default:  return "?"
        }
    }
}
