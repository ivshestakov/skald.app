import AppKit
import ApplicationServices

/// NSPanel subclass that can become the key window even with a borderless
/// style mask, and forwards Escape through an explicit callback. Without
/// the first override, typing into our text field wouldn't work (borderless
/// panels don't accept keyboard focus by default). Without the cancelOperation
/// override, Escape during the loading state wouldn't fire — the input field
/// is hidden then, so its delegate never sees the key.
private final class FloatingPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

/// Contents of the tone popover — the same ToneSlider shown in the
/// Settings Style tab, with a big colour-tinted current-tone label and
/// its description. Tapping the tone pill in the input panel surfaces
/// this inline instead of opening the full Settings window.
private final class TonePopoverContent: NSViewController {

    let slider         = ToneSlider()
    let titleLabel     = NSTextField(labelWithString: "")
    let subtitleLabel  = NSTextField(wrappingLabelWithString: "")

    /// Fired whenever the user moves the slider to a new tone. The panel
    /// uses this to update its background / border / pill visuals live.
    var onChange: ((Tone) -> Void)?

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 120))

        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.onChange = { [weak self] tone in
            Settings.shared.tone = tone
            self?.refreshLabels()
            self?.onChange?(tone)
        }

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [slider, titleLabel, subtitleLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.setCustomSpacing(10, after: slider)
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor,  constant: 16),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: root.topAnchor,           constant: 14),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -14),

            slider.widthAnchor.constraint(equalTo: stack.widthAnchor),
            subtitleLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        self.view = root

        slider.selectedTone = Settings.shared.tone
        refreshLabels()

        preferredContentSize = NSSize(width: 480, height: 112)
    }

    private func refreshLabels() {
        let tone = slider.selectedTone
        titleLabel.stringValue = tone.shortLabel
        titleLabel.textColor = tone.textColor
        subtitleLabel.stringValue = tone.subtitle
    }
}

/// Button showing the currently configured tone as an emoji inside a
/// colour-tinted pill. Enabled only when style adaptation is on AND the
/// effective engine is Claude (since other engines ignore tone directives).
/// Tap surfaces a tone-slider popover anchored to the button.
private final class TonePillButton: NSButton {

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryChange)
        imagePosition = .imageOnly
        (cell as? NSButtonCell)?.backgroundColor = .clear
    }

    /// Apply tone visuals. Flat SF symbol in a single neutral colour
    /// (matching the offline icon), with the inactive state expressed
    /// purely through alpha — no per-tone tint, no pill background,
    /// no ring. Reads as part of the typographic surface, not as a
    /// decorative button.
    func apply(tone: Tone, active: Bool) {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        image = NSImage(
            systemSymbolName: tone.symbolName,
            accessibilityDescription: tone.displayName
        )?.withSymbolConfiguration(config)
        contentTintColor = NSColor(white: 1, alpha: 0.92)

        isEnabled = active
        alphaValue = active ? 1.0 : 0.32

        toolTip = active
            ? "Tone: \(tone.displayName). Click to adjust."
            : "Tone: \(tone.displayName) — not applied (style adaptation off, or engine isn't Claude)."
    }
}

/// NSTextField subclass to customise the blinking caret colour and to
/// block macOS's default focus-ring halo.
private final class InputField: NSTextField {
    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok, let editor = currentEditor() as? NSTextView {
            editor.insertionPointColor = NSColor(
                calibratedRed: 0.35, green: 0.66, blue: 1.0, alpha: 1.0
            )
        }
        return ok
    }
}

final class SkaldPanel: NSObject {

    // Visible card size — the NSPanel is sized exactly to the card; the
    // native NSWindow shadow (hasShadow = true) gives us the outer glow,
    // and NSVisualEffectView gives us real behind-window blur.
    private let cardWidth:  CGFloat = 560
    private let cardHeight: CGFloat = 72
    private let bottomMargin: CGFloat = 100

    private var panel: FloatingPanel?
    private var input: InputField?
    private var tonePill: TonePillButton?
    private var offlineButton: NSButton?
    private var toneOverlay: NSView?
    private var toneGradient: CAGradientLayer?
    private var tonePopover: NSPopover?
    private var inputRow: NSStackView?
    private var loaderRow: NSStackView?
    private let spinner = NSProgressIndicator()
    private let loaderLabel = NSTextField(labelWithString: "Translating…")
    private var previousApp: NSRunningApplication?
    private var clickMonitor: Any?
    // Invalidates in-flight completions if the user cancels (Escape /
    // outside click) before the network call returns.
    private var requestToken: UUID?
    // User-forced offline override. When this is true, or the NetworkMonitor
    // reports no connectivity, we route translations through Apple's
    // on-device engine regardless of what Settings says.
    private var userOfflineOverride: Bool = false

    // MARK: show / hide

    func show(previousApp: NSRunningApplication?) {
        self.previousApp = previousApp

        if panel == nil { build() }
        guard let panel, let input else { return }

        input.stringValue = ""
        setLoading(false)
        updateOfflineVisual()
        updateStyleAccent()
        updateTonePill()

        if let screen = NSScreen.main {
            let sf = screen.visibleFrame
            let x = sf.minX + (sf.width - cardWidth) / 2
            let y = sf.minY + bottomMargin
            panel.setFrame(NSRect(x: x, y: y, width: cardWidth, height: cardHeight),
                           display: true)
        }

        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(input)

        // Tiny fade-in for polish.
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1.0
        }

        installClickMonitor()
    }

    func dismiss() {
        requestToken = nil             // invalidate any in-flight translate()
        spinner.stopAnimation(nil)
        tonePopover?.close()
        tonePopover = nil
        removeClickMonitor()
        panel?.orderOut(nil)
    }

    // MARK: build

    private func build() {
        let p = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: cardWidth, height: cardHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .modalPanel
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.worksWhenModal = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        // Force dark vibrancy regardless of system appearance: the HUD
        // material renders light under light mode, which would make our
        // white text unreadable.
        p.appearance = NSAppearance(named: .darkAqua)

        // Root content view — rounded, clips the blur layer to a pill shape.
        let root = NSView(frame: NSRect(x: 0, y: 0, width: cardWidth, height: cardHeight))
        root.wantsLayer = true
        root.layer?.cornerRadius = 16
        root.layer?.masksToBounds = true
        root.layer?.borderWidth = 0.5
        root.layer?.borderColor = NSColor(white: 1, alpha: 0.10).cgColor
        p.contentView = root

        // Native behind-window vibrancy — this is the "real" glass.
        let blur = NSVisualEffectView(frame: root.bounds)
        blur.autoresizingMask = [.width, .height]
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        root.addSubview(blur)

        // Tone tint overlay — vertical gradient (light at top, dense at
        // bottom) sitting between the blur and the controls. The light
        // top lets the behind-window blur shine through, the denser
        // bottom anchors the tone identity. Gives a "tinted glass" feel
        // rather than a flat watercolour wash.
        let tint = NSView(frame: root.bounds)
        tint.autoresizingMask = [.width, .height]
        tint.wantsLayer = true
        tint.layer?.masksToBounds = true

        let grad = CAGradientLayer()
        grad.frame = tint.bounds
        grad.startPoint = CGPoint(x: 0.5, y: 0.0)   // top mid
        grad.endPoint   = CGPoint(x: 0.5, y: 1.0)   // bottom mid
        grad.colors = [NSColor.clear.cgColor, NSColor.clear.cgColor]
        tint.layer?.addSublayer(grad)
        root.addSubview(tint)
        self.toneOverlay  = tint
        self.toneGradient = grad

        // Top-edge hairline highlight — 1pt of white catching "light" at
        // the curved upper rim. Standard glass-morphism trick that adds
        // a lot of depth for almost no code.
        let topEdge = NSView(frame: NSRect(
            x: 0, y: cardHeight - 1, width: cardWidth, height: 1
        ))
        topEdge.autoresizingMask = [.width, .minYMargin]
        topEdge.wantsLayer = true
        topEdge.layer?.backgroundColor = NSColor(white: 1, alpha: 0.22).cgColor
        root.addSubview(topEdge)

        // Text input
        let field = InputField()
        field.translatesAutoresizingMaskIntoConstraints = false
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.placeholderAttributedString = NSAttributedString(
            string: "translate…",
            attributes: [
                .foregroundColor: NSColor(white: 1, alpha: 0.72),
                .font: NSFont.systemFont(ofSize: 20, weight: .medium),
            ]
        )
        field.font = NSFont.systemFont(ofSize: 20, weight: .medium)
        field.textColor = .white
        field.delegate = self
        field.target = self
        field.action = #selector(onEnter)
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.lineBreakMode = .byClipping
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Tone pill — shows the configured tone's emoji. Tapping it opens
        // Settings on the Style tab. Disabled when tone isn't being applied.
        let pill = TonePillButton(frame: .zero)
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.target = self
        pill.action = #selector(openStyleSettings)
        pill.setContentHuggingPriority(.required, for: .horizontal)

        // Offline toggle — flat SF symbol in the same neutral colour as
        // the tone icon. No pill chrome; state shown via icon shape
        // (wifi ↔ wifi.slash) and (when forced offline) alpha only.
        let off = NSButton()
        off.translatesAutoresizingMaskIntoConstraints = false
        off.isBordered = false
        off.bezelStyle = .regularSquare
        off.setButtonType(.momentaryChange)
        off.imagePosition = .imageOnly
        off.target = self
        off.action = #selector(toggleOfflineOverride)
        off.setContentHuggingPriority(.required, for: .horizontal)

        // Row that shows when we're accepting input.
        let inputStack = NSStackView(views: [field, pill, off])
        inputStack.orientation = .horizontal
        inputStack.alignment = .centerY
        inputStack.spacing = 10
        inputStack.setCustomSpacing(14, after: field)
        inputStack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(inputStack)

        // Row that replaces the input while a translation is in flight.
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.isDisplayedWhenStopped = false

        loaderLabel.translatesAutoresizingMaskIntoConstraints = false
        loaderLabel.font = .systemFont(ofSize: 16, weight: .regular)
        loaderLabel.textColor = NSColor(white: 1, alpha: 0.85)

        let loaderStack = NSStackView(views: [spinner, loaderLabel])
        loaderStack.orientation = .horizontal
        loaderStack.alignment = .centerY
        loaderStack.spacing = 10
        loaderStack.translatesAutoresizingMaskIntoConstraints = false
        loaderStack.isHidden = true
        root.addSubview(loaderStack)

        NSLayoutConstraint.activate([
            inputStack.leadingAnchor.constraint(equalTo: root.leadingAnchor,  constant: 20),
            inputStack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            inputStack.centerYAnchor.constraint(equalTo: root.centerYAnchor),

            pill.widthAnchor.constraint(equalToConstant: 36),
            pill.heightAnchor.constraint(equalToConstant: 28),
            off.widthAnchor.constraint(equalToConstant: 32),
            off.heightAnchor.constraint(equalToConstant: 28),

            loaderStack.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            loaderStack.centerYAnchor.constraint(equalTo: root.centerYAnchor),
        ])

        // Escape during loading state (when field isn't first responder).
        p.onCancel = { [weak self] in self?.dismiss() }

        self.panel = p
        self.input = field
        self.tonePill = pill
        self.offlineButton = off
        self.inputRow = inputStack
        self.loaderRow = loaderStack

        // Observe network reachability so the offline visual and effective
        // engine flip automatically when connectivity changes.
        NetworkMonitor.shared.onChange = { [weak self] _ in
            self?.updateOfflineVisual()
        }
        updateOfflineVisual()
    }

    // MARK: offline toggle

    /// The override the user can flip via the inline icon. We always route
    /// to Apple's on-device engine when `true`, or when the machine is
    /// currently offline per NetworkMonitor, regardless of this flag.
    private func isEffectivelyOffline() -> Bool {
        userOfflineOverride || NetworkMonitor.shared.isOffline
    }

    private func effectiveEngine() -> Engine {
        isEffectivelyOffline() ? .apple : Settings.shared.engine
    }

    @objc private func toggleOfflineOverride() {
        userOfflineOverride.toggle()
        updateOfflineVisual()
    }

    private func updateOfflineVisual() {
        guard let b = offlineButton else { return }
        let offline     = isEffectivelyOffline()
        let forcedByNet = NetworkMonitor.shared.isOffline
        let engine      = effectiveEngine()

        let symbolName = offline ? "wifi.slash" : "wifi"
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        b.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)

        b.contentTintColor = NSColor(white: 1, alpha: 0.92)
        // No pill / ring — match the flat tone icon. Slight alpha drop
        // when offline is forced by the network (the user can't toggle
        // it then) so it reads as "system status" rather than control.
        b.alphaValue = (forcedByNet && !userOfflineOverride) ? 0.85 : 1.0

        b.toolTip = {
            if forcedByNet && !userOfflineOverride {
                return "No internet — using Apple on-device translation. Will switch back to \(Settings.shared.engine.displayName) when the connection returns."
            } else if userOfflineOverride {
                return "Offline mode — using Apple on-device translation. Click to use \(Settings.shared.engine.displayName)."
            } else {
                return "Using \(engine.displayName). Click to force offline (Apple on-device)."
            }
        }()

        // Engine change affects whether tone accent + pill apply (Claude only).
        updateStyleAccent()
        updateTonePill()
    }

    // MARK: tone pill + style accent

    /// Whether the tone directive will actually influence the next call —
    /// i.e. style adaptation is enabled AND the effective engine is Claude.
    private func isToneActive() -> Bool {
        Settings.shared.adaptStyleEnabled && effectiveEngine() == .claude
    }

    private func updateTonePill() {
        tonePill?.apply(tone: Settings.shared.tone, active: isToneActive())
    }

    @objc private func openStyleSettings() {
        guard let pill = tonePill else { return }

        // Toggle: if already showing, tap again closes.
        if let existing = tonePopover, existing.isShown {
            existing.close()
            tonePopover = nil
            return
        }

        let content = TonePopoverContent()
        content.onChange = { [weak self] _ in
            // Live-update the card's background tint, border, and pill
            // colour as the user drags the slider.
            self?.updateStyleAccent()
            self?.updateTonePill()
        }

        let pop = NSPopover()
        pop.behavior = .transient          // outside-click dismisses
        pop.animates = true
        pop.contentViewController = content
        pop.show(relativeTo: pill.bounds, of: pill, preferredEdge: .maxY)
        tonePopover = pop
    }

    private func updateStyleAccent() {
        guard let root = panel?.contentView else { return }

        let shouldAccent = Settings.shared.adaptStyleEnabled
                        && effectiveEngine() == .claude

        // Gradient changes shouldn't animate every time — turn them off
        // for the implicit setter so the colour swap is instant.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        if shouldAccent {
            let tone = Settings.shared.tone
            root.layer?.borderColor = tone.color.withAlphaComponent(0.65).cgColor
            root.layer?.borderWidth = 1.0
            // Top is barely tinted (lets the behind-window blur show
            // through, gives the glass an airy feel); bottom is dense
            // (anchors the tone identity).
            toneGradient?.colors = [
                tone.color.withAlphaComponent(0.04).cgColor,
                tone.color.withAlphaComponent(0.32).cgColor,
            ]
        } else {
            root.layer?.borderColor = NSColor(white: 1, alpha: 0.10).cgColor
            root.layer?.borderWidth = 0.5
            toneGradient?.colors = [
                NSColor.clear.cgColor,
                NSColor.clear.cgColor,
            ]
        }
    }

    // MARK: loading state

    private func setLoading(_ loading: Bool) {
        inputRow?.isHidden  = loading
        loaderRow?.isHidden = !loading
        if loading {
            loaderLabel.stringValue = "Translating via \(effectiveEngine().displayName)…"
            spinner.startAnimation(nil)
            // First responder is lost when the field hides; make the panel
            // itself the responder so Escape reaches `cancelOperation`.
            panel?.makeFirstResponder(nil)
        } else {
            spinner.stopAnimation(nil)
        }
    }

    // MARK: events

    @objc private func onEnter() {
        guard let input else { return }
        let text = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            dismiss()
            return
        }

        // Keep the panel visible but swap in the loader so the user sees
        // something is happening between Enter and paste. The panel is
        // dismissed only once the result lands.
        let token = UUID()
        requestToken = token
        setLoading(true)

        translate(text, engine: effectiveEngine()) { [weak self] result in
            guard let self, self.requestToken == token else { return }
            switch result {
            case .success(let translated):
                self.dismiss()
                self.pasteBack(translated)
            case .failure(let err):
                self.dismiss()
                NSLog("Skald: translate error: %@", String(describing: err))
                Self.showTranslateError(err)
            }
        }
    }

    private static func showTranslateError(_ err: Error) {
        let alert = NSAlert()
        alert.messageText = "Translation failed"
        alert.informativeText = String(describing: err)
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")

        // For missing-key errors, offer a shortcut to open Settings.
        let offersSettings: Bool = {
            if case TranslateError.missingKey = err { return true }
            return false
        }()
        if offersSettings {
            alert.addButton(withTitle: "Open Settings…")
        }

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if offersSettings, response == .alertSecondButtonReturn {
            (NSApp.delegate as? AppDelegate)?.openSettings()
        }
    }

    // MARK: paste

    private func pasteBack(_ text: String) {
        // Because the panel is .nonactivatingPanel, our process never stole
        // frontmost status — the user's original app is still frontmost,
        // so ⌘V goes directly to them.
        let oldClipboard = NSPasteboard.general.string(forType: .string)

        guard AXIsProcessTrusted() else {
            // Leave the translation on the clipboard so nothing is lost,
            // and tell the user exactly what needs to happen.
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            Self.showAccessibilityAlert()
            return
        }
        Pasteboard.pasteAndRestore(text: text, restoreClipboard: oldClipboard)
    }

    private static func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Skald needs Accessibility"
        alert.informativeText = """
            The translation is on your clipboard — paste with ⌘V.

            To enable automatic paste, add Skald to
            System Settings → Privacy & Security → Accessibility.
            After granting, quit and relaunch Skald from the menu bar.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: click-outside-to-dismiss

    private func installClickMonitor() {
        removeClickMonitor()
        // Global monitor fires only for clicks in OTHER apps — exactly what
        // we want. Clicks inside our own panel don't fire it, so the user
        // can freely click in the text field without closing the panel.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            self?.dismiss()
        }
    }

    private func removeClickMonitor() {
        if let m = clickMonitor {
            NSEvent.removeMonitor(m)
            clickMonitor = nil
        }
    }
}

// MARK: - NSTextFieldDelegate

extension SkaldPanel: NSTextFieldDelegate {

    // Kept empty so the NSTextFieldDelegate conformance still has a method
    // to hook into if we bring back a live-update indicator later.
    func controlTextDidChange(_ notification: Notification) {}

    func control(_ control: NSControl,
                 textView: NSTextView,
                 doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            dismiss()
            return true
        }
        return false
    }
}
