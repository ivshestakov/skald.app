import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var hotKey2: HotKey?
    private let panel = SkaldPanel()
    private var settingsWC: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        setupStatusBar()
        setupHotKey()
        promptAccessibilityIfNeeded()
        _ = Updater.shared        // boots Sparkle's background check
    }

    /// Skald is a menu-bar utility (LSUIElement = true) so the menu bar
    /// shows nothing — but macOS still needs an `NSApp.mainMenu` for
    /// keyboard-shortcut routing (⌘V / ⌘C / ⌘X / ⌘A) and for the system
    /// to expose dictation on focused text fields. Without this the
    /// input panel can't be pasted into and Whisper-style dictation
    /// helpers fail to recognise the field as a regular text input.
    private func installMainMenu() {
        let mainMenu = NSMenu()

        // App menu — first item, conventionally invisible-titled.
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "About Skald",
            action: #selector(showAbout),
            keyEquivalent: ""
        ).target = self
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit Skald",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        // Edit menu — the actual reason we're installing this. The
        // selectors are forwarded down the responder chain to whatever
        // text field is first responder, which gives us standard
        // copy/paste/undo behaviour for free.
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(
            withTitle: "Undo",
            action: Selector(("undo:")),
            keyEquivalent: "z"
        )
        let redo = editMenu.addItem(
            withTitle: "Redo",
            action: Selector(("redo:")),
            keyEquivalent: "z"
        )
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(
            withTitle: "Cut",
            action: #selector(NSText.cut(_:)),
            keyEquivalent: "x"
        )
        editMenu.addItem(
            withTitle: "Copy",
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        )
        editMenu.addItem(
            withTitle: "Paste",
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        )
        editMenu.addItem(
            withTitle: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )
        editMenu.addItem(.separator())
        // Adding this advertises the field as dictation-capable to the
        // system. macOS ties Edit → Start Dictation… to the focused
        // responder via `startDictation:`.
        editMenu.addItem(
            withTitle: "Start Dictation…",
            action: Selector(("startDictation:")),
            keyEquivalent: ""
        )
        editMenu.addItem(
            withTitle: "Emoji & Symbols",
            action: #selector(NSApplication.orderFrontCharacterPalette(_:)),
            keyEquivalent: " "
        )
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: status bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "character.bubble",
                                   accessibilityDescription: "Skald") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "T"
            }
        }

        let menu = NSMenu()
        menu.delegate = self     // for live update of "Launch at Login" check

        let openItem = menu.addItem(
            withTitle: "Open  \(currentHotkeyDisplay())",
            action: #selector(showPanel),
            keyEquivalent: ""
        )
        openItem.target = self
        openItem.identifier = NSUserInterfaceItemIdentifier("open-panel")

        menu.addItem(.separator())
        let settingsItem = menu.addItem(withTitle: "Settings…",
                                        action: #selector(openSettings),
                                        keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.target = self

        let loginItem = menu.addItem(withTitle: "Launch at Login",
                                     action: #selector(toggleLoginItem),
                                     keyEquivalent: "")
        loginItem.target = self
        loginItem.identifier = NSUserInterfaceItemIdentifier("login-item")

        menu.addItem(withTitle: "Accessibility settings…",
                     action: #selector(openAccessibility),
                     keyEquivalent: "").target = self

        menu.addItem(.separator())

        let aboutItem = menu.addItem(withTitle: "About Skald",
                                     action: #selector(showAbout),
                                     keyEquivalent: "")
        aboutItem.target = self

        let updateItem = menu.addItem(withTitle: "Check for Updates…",
                                      action: #selector(checkForUpdates),
                                      keyEquivalent: "")
        updateItem.target = self

        menu.addItem(withTitle: "Quit Skald",
                     action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")

        statusItem.menu = menu
    }

    // MARK: NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        // Refresh the "Launch at Login" check before the menu draws.
        if let item = menu.items.first(where: {
            $0.identifier?.rawValue == "login-item"
        }) {
            item.state = LoginItem.isRegistered ? .on : .off
        }
    }

    // MARK: global hotkey

    private func setupHotKey() {
        registerHotKey()
    }

    /// Public entry point so the Settings recorder can re-register the
    /// hotkey after the user changes the combination.
    func reloadHotKey() {
        registerHotKey()
        refreshOpenMenuTitle()
    }

    private func registerHotKey() {
        hotKey  = nil   // unregisters via deinit
        hotKey2 = nil

        let kc   = UInt32(Settings.shared.hotkeyKeyCode)
        let mods = Self.carbonModifiers(from: Settings.shared.hotkeyModifiers)
        hotKey = HotKey(keyCode: kc, modifiers: mods) { [weak self] in
            self?.showPanel()
        }
        if hotKey == nil {
            NSLog("Skald: failed to register primary hotkey. Is another app holding it?")
        }

        let kc2   = UInt32(Settings.shared.hotkey2KeyCode)
        let mods2 = Self.carbonModifiers(from: Settings.shared.hotkey2Modifiers)
        hotKey2 = HotKey(keyCode: kc2, modifiers: mods2) {
            QuickTranslator.run()
        }
        if hotKey2 == nil {
            NSLog("Skald: failed to register quick-translate hotkey.")
        }
    }

    private static func carbonModifiers(
        from ns: NSEvent.ModifierFlags
    ) -> HotKeyModifiers {
        var out: HotKeyModifiers = []
        if ns.contains(.command) { out.insert(.command) }
        if ns.contains(.option)  { out.insert(.option)  }
        if ns.contains(.control) { out.insert(.control) }
        if ns.contains(.shift)   { out.insert(.shift)   }
        return out
    }

    /// Compact glyph string for the currently configured hotkey, used in
    /// the status-bar menu title (e.g. "⌥/", "⌘⇧K").
    private func currentHotkeyDisplay() -> String {
        let mods = Settings.shared.hotkeyModifiers
        var prefix = ""
        if mods.contains(.control) { prefix += "⌃" }
        if mods.contains(.option)  { prefix += "⌥" }
        if mods.contains(.shift)   { prefix += "⇧" }
        if mods.contains(.command) { prefix += "⌘" }
        return prefix + Settings.shared.hotkeyDisplay
    }

    /// Refresh the status-bar menu item's title after the hotkey changes.
    private func refreshOpenMenuTitle() {
        guard let menu = statusItem.menu,
              let item = menu.items.first(where: {
                  $0.identifier?.rawValue == "open-panel"
              })
        else { return }
        item.title = "Open  \(currentHotkeyDisplay())"
    }

    // MARK: actions

    @objc private func showPanel() {
        let prev = NSWorkspace.shared.frontmostApplication
        panel.show(previousApp: prev)
    }

    @objc private func openAccessibility() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func openSettings() {
        showSettings(tab: nil)
    }

    @objc private func toggleLoginItem() {
        LoginItem.setRegistered(!LoginItem.isRegistered)
    }

    @objc private func checkForUpdates() {
        Updater.shared.checkForUpdates()
    }

    @objc private func showAbout() {
        let credits = NSMutableAttributedString()
        credits.append(NSAttributedString(
            string: "Skald translates short phrases on the fly. Trigger the hotkey, type, hit Enter — the translation lands where your cursor was.\n\n",
            attributes: [
                .foregroundColor: NSColor.labelColor,
                .font: NSFont.systemFont(ofSize: 11),
            ]
        ))
        credits.append(NSAttributedString(
            string: "Engines: Apple (on-device) · Google · DeepL · Claude.\n\n",
            attributes: [
                .foregroundColor: NSColor.secondaryLabelColor,
                .font: NSFont.systemFont(ofSize: 11),
            ]
        ))
        credits.append(NSAttributedString(
            string: "MIT-licensed. github.com/ivshestakov/skald",
            attributes: [
                .foregroundColor: NSColor.secondaryLabelColor,
                .font: NSFont.systemFont(ofSize: 11),
            ]
        ))

        NSApp.orderFrontStandardAboutPanel(options: [
            .credits:               credits,
            .applicationName:       "Skald",
        ])
        NSApp.activate(ignoringOtherApps: true)
    }

    func showSettings(tab tabIdentifier: String?) {
        if settingsWC == nil {
            settingsWC = SettingsWindowController()
        }
        settingsWC?.showWindow(nil)
        if let tabIdentifier {
            settingsWC?.selectTab(tabIdentifier)
        }
    }

    // MARK: accessibility

    private func promptAccessibilityIfNeeded() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options: NSDictionary = [key: true]
        let trusted = AXIsProcessTrustedWithOptions(options)
        NSLog("Skald: accessibility trusted = %@", trusted ? "YES" : "NO")
    }
}
