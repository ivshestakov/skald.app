import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Accessory = menu-bar only, no Dock icon, no main menu.
app.setActivationPolicy(.accessory)
app.run()
