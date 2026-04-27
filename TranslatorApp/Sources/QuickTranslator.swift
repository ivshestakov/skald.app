import AppKit
import ApplicationServices

/// Implements the "second hotkey" flow: translate the current selection
/// in place (if anything's selected) or, failing that, translate the
/// clipboard contents and paste at the cursor.
///
/// We can't ask AppKit "is there a selection?" portably across apps —
/// AX is patchy in the wild — so we use a clipboard-diff trick:
///   1. Snapshot the pasteboard `changeCount` and string contents.
///   2. Synthesise ⌘C.
///   3. Wait briefly. If `changeCount` advanced, the host app actually
///      copied something → there was a selection. Otherwise → no
///      selection, fall back to translating whatever was on the clipboard.
///   4. Translate.
///   5. Place result on the clipboard, synthesise ⌘V, restore the
///      original clipboard a moment later.
///
/// The natural ⌘V-after-⌘C semantics are exactly what we want: a copied
/// selection stays highlighted, so ⌘V replaces it. With no selection,
/// ⌘V just inserts at the cursor.
enum QuickTranslator {

    private static let copyPropagationDelay: TimeInterval = 0.15

    static func run() {
        guard AXIsProcessTrusted() else {
            showAlert(
                title: "Skald needs Accessibility",
                detail: """
                    Quick translate uses simulated ⌘C / ⌘V to read your selection \
                    and paste the translation. Grant Accessibility in
                    System Settings → Privacy & Security → Accessibility.
                    """
            )
            return
        }

        let pb = NSPasteboard.general
        let originalClipboard = pb.string(forType: .string)
        let originalChangeCount = pb.changeCount

        Pasteboard.sendCmdC()

        // Give the host app time to actually update the pasteboard.
        DispatchQueue.main.asyncAfter(deadline: .now() + copyPropagationDelay) {
            let copiedSomething = pb.changeCount != originalChangeCount
            let copied = copiedSomething ? pb.string(forType: .string) : nil

            let source: String
            if let copied, !copied.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                source = copied
            } else if let originalClipboard,
                      !originalClipboard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                source = originalClipboard
            } else {
                NSSound.beep()
                return
            }

            // Pick the engine the same way the panel does: respect the
            // network state (auto-fall-back to Apple when offline) but
            // ignore the user's panel-local offline override since the
            // panel isn't shown in this flow.
            let engine: Engine = NetworkMonitor.shared.isOffline
                ? .apple
                : Settings.shared.engine

            translate(source, engine: engine) { result in
                switch result {
                case .success(let translated):
                    Pasteboard.pasteAndRestore(
                        text: translated,
                        restoreClipboard: originalClipboard
                    )
                case .failure(let err):
                    NSLog("Skald: quick-translate error: %@", String(describing: err))
                    showAlert(
                        title: "Translation failed",
                        detail: String(describing: err)
                    )
                }
            }
        }
    }

    private static func showAlert(title: String, detail: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = detail
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }
}
