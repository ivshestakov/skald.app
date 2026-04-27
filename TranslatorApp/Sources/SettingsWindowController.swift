import AppKit

final class SettingsWindowController: NSWindowController, NSWindowDelegate {

    // MARK: controls

    // Languages tab
    private let primaryPopup   = NSPopUpButton()
    private let secondaryPopup = NSPopUpButton()
    private let langHintLabel  = NSTextField(wrappingLabelWithString: "")

    // Model tab
    private let enginePopup      = NSPopUpButton()
    private let claudeModelPopup = NSPopUpButton()
    private let apiKeyField      = NSSecureTextField()
    private let descriptionLabel = NSTextField(wrappingLabelWithString: "")
    private let howToLabel       = NSTextField(wrappingLabelWithString: "")
    private let howToHeader      = NSTextField(labelWithString: "")
    private let testButton       = NSButton()
    private let statusLabel      = NSTextField(labelWithString: "")

    private var apiKeyRow:     NSStackView!
    private var claudeModelRow: NSStackView!

    // Style tab
    private let adaptToggle       = NSButton(checkboxWithTitle: "Adapt translation style", target: nil, action: nil)
    private let toneSlider        = ToneSlider()
    private let toneTitleLabel    = NSTextField(labelWithString: "")
    private let toneSubtitleLabel = NSTextField(wrappingLabelWithString: "")
    private let styleHintLabel    = NSTextField(wrappingLabelWithString: "")

    private var sidebarItems: [String: SidebarItemView] = [:]
    private var contentScroll: NSScrollView?
    private var sectionViewCache: [String: NSView] = [:]
    private var titleLabel: NSTextField?

    // MARK: init

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 740, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Skald"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
        window.delegate = self
        buildUI()
    }

    // MARK: layout

    private func buildUI() {
        guard let window, let content = window.contentView else { return }

        // Frosted glass background spans the full window (including under
        // the now-transparent title bar) so the chrome blends in.
        let blur = NSVisualEffectView(frame: content.bounds)
        blur.autoresizingMask = [.width, .height]
        blur.material = .sidebar
        blur.blendingMode = .behindWindow
        blur.state = .active
        content.addSubview(blur)

        // -------- Sidebar --------
        let appNameLabel = NSTextField(labelWithString: "Skald")
        appNameLabel.font = NSFont.systemFont(ofSize: 17, weight: .semibold)
        appNameLabel.textColor = .labelColor
        appNameLabel.translatesAutoresizingMaskIntoConstraints = false

        let sidebarStack = NSStackView()
        sidebarStack.orientation = .vertical
        sidebarStack.alignment = .leading
        sidebarStack.spacing = 4
        sidebarStack.translatesAutoresizingMaskIntoConstraints = false

        struct Section {
            let id: String
            let symbol: String
            let title: String
        }
        let sections: [Section] = [
            .init(id: "langs",     symbol: "globe",                  title: "Languages"),
            .init(id: "model",     symbol: "cpu",                    title: "Model"),
            .init(id: "style",     symbol: "paintbrush.pointed.fill", title: "Style"),
            .init(id: "shortcuts", symbol: "command",                title: "Shortcuts"),
        ]

        for section in sections {
            let item = SidebarItemView(
                identifier: section.id,
                symbolName: section.symbol,
                title: section.title
            )
            item.translatesAutoresizingMaskIntoConstraints = false
            item.onClick = { [weak self] in self?.selectSection(section.id) }
            sidebarItems[section.id] = item
            sidebarStack.addArrangedSubview(item)
            // Stretch each item to full sidebar width.
            item.widthAnchor.constraint(equalTo: sidebarStack.widthAnchor).isActive = true
        }

        let sidebarContainer = NSView()
        sidebarContainer.translatesAutoresizingMaskIntoConstraints = false
        sidebarContainer.addSubview(appNameLabel)
        sidebarContainer.addSubview(sidebarStack)
        content.addSubview(sidebarContainer)

        NSLayoutConstraint.activate([
            sidebarContainer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            sidebarContainer.topAnchor.constraint(equalTo: content.topAnchor),
            sidebarContainer.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            sidebarContainer.widthAnchor.constraint(equalToConstant: 180),

            appNameLabel.leadingAnchor.constraint(equalTo: sidebarContainer.leadingAnchor, constant: 22),
            appNameLabel.topAnchor.constraint(equalTo: sidebarContainer.topAnchor, constant: 38),

            sidebarStack.leadingAnchor.constraint(equalTo: sidebarContainer.leadingAnchor, constant: 12),
            sidebarStack.trailingAnchor.constraint(equalTo: sidebarContainer.trailingAnchor, constant: -12),
            sidebarStack.topAnchor.constraint(equalTo: appNameLabel.bottomAnchor, constant: 18),
        ])

        // -------- Content area --------
        let title = NSTextField(labelWithString: "")
        title.translatesAutoresizingMaskIntoConstraints = false
        title.font = NSFont.systemFont(ofSize: 22, weight: .bold)
        title.textColor = .labelColor
        self.titleLabel = title

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        self.contentScroll = scroll

        content.addSubview(title)
        content.addSubview(scroll)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: sidebarContainer.trailingAnchor, constant: 28),
            title.topAnchor.constraint(equalTo: content.topAnchor, constant: 38),
            title.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -28),

            scroll.leadingAnchor.constraint(equalTo: sidebarContainer.trailingAnchor, constant: 28),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            scroll.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 16),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -28),
        ])

        // Build every section eagerly so loadFromSettings() can populate
        // controls regardless of which one is currently visible. (The
        // popups and conditional rows for the Model section, in
        // particular, must exist before refreshForEngine() runs.)
        for id in ["langs", "model", "style", "shortcuts"] {
            sectionViewCache[id] = CardView(content: buildSectionInner(id))
        }

        selectSection("langs")
    }

    private func buildSectionInner(_ id: String) -> NSView {
        switch id {
        case "langs":     return buildLanguagesView()
        case "model":     return buildModelView()
        case "style":     return buildStyleView()
        case "shortcuts": return buildShortcutsView()
        default:          return NSView()
        }
    }

    /// Switch the visible section. Section views are built once during
    /// buildUI() and reused on each selection.
    private func selectSection(_ id: String) {
        for (key, item) in sidebarItems {
            item.isSelected = (key == id)
        }
        titleLabel?.stringValue = sectionTitle(for: id) ?? ""

        guard let card = sectionViewCache[id] else { return }
        card.translatesAutoresizingMaskIntoConstraints = false
        // A card may already be attached to a previous flipped container.
        card.removeFromSuperview()

        // Wrap the card in a flipped container so the scroll view's natural
        // top-down origin matches the card sitting at the top.
        let flipped = FlippedContainerView()
        flipped.translatesAutoresizingMaskIntoConstraints = false
        flipped.addSubview(card)

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: flipped.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: flipped.trailingAnchor),
            card.topAnchor.constraint(equalTo: flipped.topAnchor),
            card.bottomAnchor.constraint(lessThanOrEqualTo: flipped.bottomAnchor),
        ])

        contentScroll?.documentView = flipped
        if let scroll = contentScroll {
            flipped.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        }
    }

    private func sectionTitle(for id: String) -> String? {
        switch id {
        case "langs":     return "Languages"
        case "model":     return "Model"
        case "style":     return "Style"
        case "shortcuts": return "Shortcuts"
        default:          return nil
        }
    }

    // MARK: Languages tab

    private func buildLanguagesView() -> NSView {
        let root = NSView()

        primaryPopup.translatesAutoresizingMaskIntoConstraints = false
        secondaryPopup.translatesAutoresizingMaskIntoConstraints = false
        for lang in Language.allCases {
            primaryPopup.addItem(withTitle:   "\(lang.flag)  \(lang.displayName)")
            secondaryPopup.addItem(withTitle: "\(lang.flag)  \(lang.displayName)")
        }
        primaryPopup.target = self
        primaryPopup.action = #selector(primaryLangChanged)
        secondaryPopup.target = self
        secondaryPopup.action = #selector(secondaryLangChanged)

        langHintLabel.font = .systemFont(ofSize: 12)
        langHintLabel.textColor = .secondaryLabelColor
        langHintLabel.stringValue = """
            Skald auto-detects which of the two languages you typed and translates into the other. \
            Detection uses Apple's on-device Natural Language framework — it runs locally and doesn't \
            send your text anywhere for language identification.

            If detection is uncertain (very short phrases, ambiguous scripts), the app defaults to \
            translating from the first language into the second.
            """

        let primaryRow   = makeRow(label: "First language",  field: primaryPopup)
        let secondaryRow = makeRow(label: "Second language", field: secondaryPopup)

        let stack = NSStackView(views: [primaryRow, secondaryRow, langHintLabel, NSView()])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor,  constant: 20),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: root.topAnchor,           constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -20),

            primaryPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 240),
            secondaryPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 240),
            langHintLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        return root
    }

    // MARK: Model tab

    private func buildModelView() -> NSView {
        let root = NSView()

        enginePopup.translatesAutoresizingMaskIntoConstraints = false
        Engine.allCases.forEach { enginePopup.addItem(withTitle: $0.displayName) }
        enginePopup.target = self
        enginePopup.action = #selector(engineChanged)

        claudeModelPopup.translatesAutoresizingMaskIntoConstraints = false
        ClaudeModel.allCases.forEach { claudeModelPopup.addItem(withTitle: $0.displayName) }
        claudeModelPopup.target = self
        claudeModelPopup.action = #selector(claudeModelChanged)

        apiKeyField.translatesAutoresizingMaskIntoConstraints = false
        apiKeyField.placeholderString = "Paste API key"
        apiKeyField.delegate = self

        descriptionLabel.font = .systemFont(ofSize: 12)
        descriptionLabel.textColor = .labelColor

        howToHeader.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        howToHeader.textColor = .secondaryLabelColor
        howToHeader.stringValue = "How to get a key"

        howToLabel.font = .systemFont(ofSize: 12)
        howToLabel.textColor = .secondaryLabelColor

        testButton.translatesAutoresizingMaskIntoConstraints = false
        testButton.title = "Test connection"
        testButton.bezelStyle = .rounded
        testButton.target = self
        testButton.action = #selector(testPressed)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let engineRow      = makeRow(label: "Engine",  field: enginePopup)
        claudeModelRow     = makeRow(label: "Model",   field: claudeModelPopup)
        apiKeyRow          = makeRow(label: "API key", field: apiKeyField)

        let testRow = NSStackView(views: [testButton, statusLabel])
        testRow.orientation = .horizontal
        testRow.alignment = .centerY
        testRow.spacing = 12
        testRow.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [
            engineRow,
            descriptionLabel,
            claudeModelRow,
            apiKeyRow,
            howToHeader,
            howToLabel,
            testRow,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.setCustomSpacing(8, after: howToHeader)
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor,  constant: 20),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: root.topAnchor,           constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -20),

            enginePopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 240),
            claudeModelPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 280),
            apiKeyField.widthAnchor.constraint(greaterThanOrEqualToConstant: 360),
            descriptionLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            howToLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            testRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        return root
    }

    // MARK: Style tab

    private func buildStyleView() -> NSView {
        let root = NSView()

        adaptToggle.target = self
        adaptToggle.action = #selector(adaptToggleChanged)
        adaptToggle.translatesAutoresizingMaskIntoConstraints = false
        adaptToggle.font = .systemFont(ofSize: 13, weight: .medium)

        styleHintLabel.font = .systemFont(ofSize: 12)
        styleHintLabel.textColor = .secondaryLabelColor
        styleHintLabel.stringValue = """
            When enabled, the tone below is injected into the Claude system prompt. \
            Costs roughly +50 input tokens per translation:
              •  Haiku 4.5  —  ~$0.00005 per request (negligible)
              •  Sonnet 4.6 —  ~$0.00015
              •  Opus 4.7   —  ~$0.00075

            Ignored by Google, DeepL, and Apple engines — those can't accept custom instructions.
            """

        toneSlider.translatesAutoresizingMaskIntoConstraints = false
        toneSlider.onChange = { [weak self] tone in
            Settings.shared.tone = tone
            self?.refreshToneLabels()
        }

        toneTitleLabel.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        toneTitleLabel.textColor = .labelColor
        toneTitleLabel.translatesAutoresizingMaskIntoConstraints = false

        toneSubtitleLabel.font = .systemFont(ofSize: 12)
        toneSubtitleLabel.textColor = .secondaryLabelColor
        toneSubtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        let sectionHeader = NSTextField(labelWithString: "Tone")
        sectionHeader.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        sectionHeader.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [
            adaptToggle,
            styleHintLabel,
            sectionHeader,
            toneSlider,
            toneTitleLabel,
            toneSubtitleLabel,
            NSView(),
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.setCustomSpacing(20, after: styleHintLabel)
        stack.setCustomSpacing(6,  after: sectionHeader)
        stack.setCustomSpacing(10, after: toneSlider)
        stack.setCustomSpacing(4,  after: toneTitleLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor,  constant: 20),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: root.topAnchor,           constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -20),

            styleHintLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            toneSlider.widthAnchor.constraint(equalTo: stack.widthAnchor),
            toneSubtitleLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        return root
    }

    private func refreshToneLabels() {
        let tone = toneSlider.selectedTone
        toneTitleLabel.stringValue = tone.shortLabel
        toneTitleLabel.textColor = tone.textColor
        toneSubtitleLabel.stringValue = tone.subtitle

        let on = adaptToggle.state == .on
        toneSlider.isEnabled = on
        toneSlider.alphaValue = on ? 1.0 : 0.45
        toneTitleLabel.alphaValue = on ? 1.0 : 0.45
        toneSubtitleLabel.alphaValue = on ? 1.0 : 0.45
    }

    @objc private func adaptToggleChanged() {
        Settings.shared.adaptStyleEnabled = adaptToggle.state == .on
        refreshToneLabels()
    }

    // MARK: Shortcuts tab

    private func buildShortcutsView() -> NSView {
        let root = NSView()

        // ── Row 1: open the input panel
        let row1 = makeShortcutRow(
            label: "Open the input panel",
            keyCode: Settings.shared.hotkeyKeyCode,
            modifiers: Settings.shared.hotkeyModifiers,
            display: Settings.shared.hotkeyDisplay,
            onChange: { kc, mods, disp in
                Settings.shared.hotkeyKeyCode  = kc
                Settings.shared.hotkeyModifiers = mods
                Settings.shared.hotkeyDisplay  = disp
                (NSApp.delegate as? AppDelegate)?.reloadHotKey()
            }
        )
        let hint1 = NSTextField(wrappingLabelWithString:
            "Brings up the glass panel — type a phrase, press Enter to translate and paste."
        )
        styleHintBody(hint1)

        // ── Row 2: quick translate (selection / clipboard)
        let row2 = makeShortcutRow(
            label: "Quick translate (selection / clipboard)",
            keyCode: Settings.shared.hotkey2KeyCode,
            modifiers: Settings.shared.hotkey2Modifiers,
            display: Settings.shared.hotkey2Display,
            onChange: { kc, mods, disp in
                Settings.shared.hotkey2KeyCode  = kc
                Settings.shared.hotkey2Modifiers = mods
                Settings.shared.hotkey2Display  = disp
                (NSApp.delegate as? AppDelegate)?.reloadHotKey()
            }
        )
        let hint2 = NSTextField(wrappingLabelWithString:
            "Press without showing the panel: if text is selected it's translated and replaced "
            + "in place; otherwise the current clipboard is translated and pasted at the cursor."
        )
        styleHintBody(hint2)

        // ── Footer hint
        let footer = NSTextField(wrappingLabelWithString:
            "Click a box to record, press the new combination. Must include at least one "
            + "modifier (⌘ ⌥ ⌃ ⇧). Press Esc to cancel a recording."
        )
        styleHintBody(footer)
        footer.textColor = NSColor.tertiaryLabelColor

        let stack = NSStackView(views: [row1, hint1, row2, hint2, footer, NSView()])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.setCustomSpacing(20, after: hint1)
        stack.setCustomSpacing(20, after: hint2)
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor,  constant: 24),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: root.topAnchor,           constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -24),

            row1.widthAnchor.constraint(equalTo: stack.widthAnchor),
            row2.widthAnchor.constraint(equalTo: stack.widthAnchor),
            hint1.widthAnchor.constraint(equalTo: stack.widthAnchor),
            hint2.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        return root
    }

    private func makeShortcutRow(
        label: String,
        keyCode: Int,
        modifiers: NSEvent.ModifierFlags,
        display: String,
        onChange: @escaping (Int, NSEvent.ModifierFlags, String) -> Void
    ) -> NSStackView {
        let title = NSTextField(labelWithString: label)
        title.font = .systemFont(ofSize: 13)
        title.textColor = .labelColor
        title.translatesAutoresizingMaskIntoConstraints = false
        title.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let recorder = ShortcutRecorderView(
            keyCode: keyCode,
            modifiers: modifiers,
            displayChar: display
        )
        recorder.translatesAutoresizingMaskIntoConstraints = false
        recorder.onChange = onChange

        let row = NSStackView(views: [title, recorder])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    private func styleHintBody(_ field: NSTextField) {
        field.font = .systemFont(ofSize: 11)
        field.textColor = .secondaryLabelColor
        field.translatesAutoresizingMaskIntoConstraints = false
    }

    private func makeRow(label: String, field: NSView) -> NSStackView {
        let l = NSTextField(labelWithString: label + ":")
        l.alignment = .right
        l.font = .systemFont(ofSize: 13)
        l.translatesAutoresizingMaskIntoConstraints = false
        l.widthAnchor.constraint(equalToConstant: 120).isActive = true

        let row = NSStackView(views: [l, field])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    // MARK: lifecycle

    override func showWindow(_ sender: Any?) {
        loadFromSettings()
        NSApp.activate(ignoringOtherApps: true)
        super.showWindow(sender)
    }

    /// Programmatically switch to a section by identifier
    /// ("langs"/"model"/"style"/"shortcuts").
    func selectTab(_ identifier: String) {
        selectSection(identifier)
    }

    func windowWillClose(_ notification: Notification) {
        commitCurrentKey()
    }

    // MARK: state

    private func loadFromSettings() {
        let s = Settings.shared

        if let idx = Language.allCases.firstIndex(of: s.primaryLanguage) {
            primaryPopup.selectItem(at: idx)
        }
        if let idx = Language.allCases.firstIndex(of: s.secondaryLanguage) {
            secondaryPopup.selectItem(at: idx)
        }
        if let idx = Engine.allCases.firstIndex(of: s.engine) {
            enginePopup.selectItem(at: idx)
        }
        if let idx = ClaudeModel.allCases.firstIndex(of: s.claudeModel) {
            claudeModelPopup.selectItem(at: idx)
        }
        adaptToggle.state = s.adaptStyleEnabled ? .on : .off
        toneSlider.selectedTone = s.tone
        refreshForEngine()
        refreshToneLabels()
    }

    private func refreshForEngine() {
        let engine = currentEngine()
        apiKeyField.stringValue = Settings.shared.apiKey(for: engine) ?? ""
        statusLabel.stringValue = ""

        switch engine {
        case .apple:
            apiKeyRow.isHidden      = true
            claudeModelRow.isHidden = true
            testButton.isHidden     = false
            descriptionLabel.stringValue = """
                Apple's on-device Translation framework (requires macOS 15.0+). Runs entirely on \
                your Mac — your text never leaves the device.

                • Cost: Free
                • Limits: None — no API keys, no quotas, no rate limits
                • Quality: Comparable to Google Translate for major language pairs
                • Offline: Fully offline after one-time model download per language pair
                • Privacy: Text stays on your Mac; no network calls during translation
                """
            howToHeader.stringValue = "How it works"
            howToLabel.stringValue = """
                1. Select "Apple" as the engine and pick languages on the Languages tab
                2. The first time you translate between a new language pair, macOS will prompt \
                   to download the translation model (~50–100 MB) — you need internet once
                3. After that, translation works fully offline
                4. Models live in System Settings → General → Language & Region → Translation Languages, \
                   where you can delete them to reclaim disk space
                """
        case .google:
            apiKeyRow.isHidden      = true
            claudeModelRow.isHidden = true
            testButton.isHidden     = true
            descriptionLabel.stringValue = """
                Google's unofficial public endpoint. Good enough for quick phrases, but quality is \
                weaker than DeepL or Claude, especially on idioms and tone.

                • Cost: Free
                • Limits: Soft rate limits; endpoint can break without notice (it is not an official API)
                • Quality: Acceptable for simple phrases
                """
            howToHeader.stringValue = "Setup"
            howToLabel.stringValue = "No API key required. Just select this engine and go."
        case .deepl:
            apiKeyRow.isHidden      = false
            claudeModelRow.isHidden = true
            testButton.isHidden     = false
            descriptionLabel.stringValue = """
                DeepL is the best traditional neural machine translator for European languages. \
                Noticeably better than Google on idioms, register, and natural-sounding phrasing.

                • Cost: Free up to 500 000 characters/month
                • Paid: €5.49/mo base + €20 per additional 1 M characters
                • Limits: Free-tier rate limits are lenient for personal use
                • Free-plan keys end in ":fx" — the app auto-routes them to api-free.deepl.com
                """
            howToHeader.stringValue = "How to get a key"
            howToLabel.stringValue = """
                1. Go to deepl.com/pro-api in your browser
                2. Click "Sign up for free" and register (email + password or via OAuth)
                3. After login, open Account → Authentication Key for DeepL API
                4. Copy the key — it will end in ":fx" for the free plan
                5. Paste it into the API key field above
                6. Click Test connection to verify
                """
        case .claude:
            apiKeyRow.isHidden      = false
            claudeModelRow.isHidden = false
            testButton.isHidden     = false
            descriptionLabel.stringValue = """
                LLM-based translation via Anthropic's Claude. Highest quality — especially on slang, \
                idioms, technical jargon, and nuanced tone. Slower than DeepL/Google (~300–500 ms) \
                but usually worth it.

                • Cost: Pay-as-you-go, no free tier
                  – Haiku 4.5: ~$0.0001 per short phrase
                  – Sonnet 4.6: ~$0.0005 per short phrase
                  – Opus 4.7: ~$0.0025 per short phrase
                • Limits: Generous rate limits for pay-as-you-go accounts
                """
            howToHeader.stringValue = "How to get a key"
            howToLabel.stringValue = """
                1. Go to console.anthropic.com
                2. Sign up (Google, GitHub, or email) and verify your account
                3. Add a billing method in Settings → Plans & Billing (required — Claude has no free tier)
                4. Deposit a small amount (e.g. $5) or enable auto-reload
                5. Open API Keys → Create Key, name it e.g. "Skald.app"
                6. Copy the key (it starts with "sk-ant-api03-…") and paste it above
                7. Click Test connection
                """
        }
    }

    private func currentEngine() -> Engine        { Engine.allCases[enginePopup.indexOfSelectedItem] }
    private func currentClaudeModel() -> ClaudeModel { ClaudeModel.allCases[claudeModelPopup.indexOfSelectedItem] }
    private func currentPrimary() -> Language     { Language.allCases[primaryPopup.indexOfSelectedItem]   }
    private func currentSecondary() -> Language   { Language.allCases[secondaryPopup.indexOfSelectedItem] }

    private func commitCurrentKey() {
        let engine = currentEngine()
        guard engine != .google else { return }
        let trimmed = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        Settings.shared.setApiKey(trimmed.isEmpty ? nil : trimmed, for: engine)
    }

    // MARK: actions

    @objc private func engineChanged() {
        commitCurrentKey()
        Settings.shared.engine = currentEngine()
        refreshForEngine()
    }

    @objc private func claudeModelChanged() {
        Settings.shared.claudeModel = currentClaudeModel()
    }

    @objc private func primaryLangChanged() {
        Settings.shared.primaryLanguage = currentPrimary()
    }

    @objc private func secondaryLangChanged() {
        Settings.shared.secondaryLanguage = currentSecondary()
    }

    @objc private func testPressed() {
        commitCurrentKey()
        statusLabel.stringValue = "Testing…"
        statusLabel.textColor = .secondaryLabelColor
        testButton.isEnabled = false

        // Send a short sample that will exercise the configured language pair.
        let primary = Settings.shared.primaryLanguage
        let sample: String
        switch primary {
        case .russian:    sample = "Привет, как дела?"
        case .ukrainian:  sample = "Привіт, як справи?"
        case .german:     sample = "Hallo, wie geht's?"
        case .french:     sample = "Bonjour, comment ça va ?"
        case .spanish:    sample = "Hola, ¿cómo estás?"
        case .italian:    sample = "Ciao, come stai?"
        case .portuguese: sample = "Olá, como vai?"
        case .polish:     sample = "Cześć, jak się masz?"
        case .dutch:      sample = "Hallo, hoe gaat het?"
        case .chinese:    sample = "你好，你好吗？"
        case .japanese:   sample = "こんにちは、お元気ですか？"
        case .korean:     sample = "안녕하세요, 어떻게 지내세요?"
        case .english:    sample = "Hello, how are you?"
        }

        translate(sample) { [weak self] result in
            guard let self else { return }
            self.testButton.isEnabled = true
            switch result {
            case .success(let text):
                self.statusLabel.stringValue = "✓ " + text
                self.statusLabel.textColor = .systemGreen
            case .failure(let err):
                self.statusLabel.stringValue = "✗ " + String(describing: err)
                self.statusLabel.textColor = .systemRed
            }
        }
    }
}

// MARK: - NSTextFieldDelegate

extension SettingsWindowController: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ notification: Notification) {
        commitCurrentKey()
    }
}
