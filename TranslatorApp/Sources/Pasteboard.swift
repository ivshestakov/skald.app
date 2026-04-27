import AppKit

/// Helpers around the general pasteboard + simulated ⌘C / ⌘V keystrokes.
/// All synthesis goes through `CGEvent.post(tap: .cghidEventTap)`, which
/// requires Accessibility permission.
enum Pasteboard {

    private static let cKeyCode: CGKeyCode = 0x08
    private static let vKeyCode: CGKeyCode = 0x09
    private static let cmdMask: CGEventFlags = .maskCommand

    static func sendCmdC() { sendKey(cKeyCode) }
    static func sendCmdV() { sendKey(vKeyCode) }

    private static func sendKey(_ keyCode: CGKeyCode) {
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
        down?.flags = cmdMask
        down?.post(tap: .cghidEventTap)
        let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
        up?.flags = cmdMask
        up?.post(tap: .cghidEventTap)
    }

    /// Put `text` on the pasteboard, simulate ⌘V at the current cursor,
    /// then restore the previous clipboard after a brief delay so we
    /// don't permanently hijack the user's paste buffer.
    static func pasteAndRestore(text: String,
                                restoreClipboard: String?,
                                preDelay: TimeInterval = 0.08) {
        DispatchQueue.main.asyncAfter(deadline: .now() + preDelay) {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
            sendCmdV()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if let restoreClipboard {
                    pb.clearContents()
                    pb.setString(restoreClipboard, forType: .string)
                }
            }
        }
    }
}
