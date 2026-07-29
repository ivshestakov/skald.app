import AppKit
import Foundation

/// Human-facing presentation of a failed translation.
///
/// Both alert sites used to show `String(describing: error)`. For anything
/// that comes back from `URLSession` that's the whole `NSError` userInfo —
/// `_kCFStreamErrorCodeKey`, nested underlying errors, task identifiers —
/// a wall of text that tells the user nothing they can act on. The dump now
/// goes to the log only; the alert gets one sentence, plus a Retry button
/// when the failure looks transient.
struct TranslateFailure {

    /// Alert headline.
    let title: String
    /// One sentence explaining what happened and what to do about it.
    let detail: String
    /// Dropped connections, timeouts, throttling, 5xx — pressing the button
    /// again is a reasonable thing to do.
    let isRetryable: Bool
    /// Credentials problem — offer a jump to Settings.
    let offersSettings: Bool

    init(_ error: Error, engine: Engine?) {
        let name = engine?.shortName ?? "The translation service"

        if let err = error as? TranslateError {
            switch err {
            case .missingKey(let eng):
                title          = "No API key for \(eng.shortName)"
                detail         = "Skald needs an API key to translate with "
                               + "\(eng.shortName). Add one in Settings → Model."
                isRetryable    = false
                offersSettings = true

            case .network(let code) where code == 401 || code == 403:
                title          = "\(name) rejected the API key"
                detail         = "The key was refused. Check it in Settings → Model."
                isRetryable    = false
                offersSettings = true

            case .network(let code) where code == 429:
                title          = "\(name) is rate-limiting"
                detail         = "Too many requests in a row. Wait a few seconds, "
                               + "then try again."
                isRetryable    = true
                offersSettings = false

            case .network(let code) where code >= 500:
                title          = "\(name) is unavailable"
                detail         = "The service is having trouble on its end "
                               + "(HTTP \(code)). This is usually temporary."
                isRetryable    = true
                offersSettings = false

            case .network(let code) where code < 0:
                title          = "Unexpected reply"
                detail         = "\(name) answered with something that isn't a "
                               + "valid HTTP response."
                isRetryable    = true
                offersSettings = false

            case .network(let code):
                title          = "\(name) returned an error"
                detail         = "The request was rejected (HTTP \(code))."
                isRetryable    = false
                offersSettings = false

            case .parse, .empty:
                title          = "Couldn't read the translation"
                detail         = "\(name) replied, but Skald couldn't make sense "
                               + "of the response."
                isRetryable    = true
                offersSettings = false

            case .provider(let message):
                title          = "\(name) reported an error"
                detail         = message
                isRetryable    = true
                offersSettings = false
            }
            return
        }

        if let err = error as? URLError {
            // The host is more useful than the engine name here — it's what
            // the user would whitelist in a VPN or look up when DNS breaks.
            let host = err.failingURL?.host ?? name
            offersSettings = false

            switch err.code {
            case .notConnectedToInternet:
                title       = "No internet connection"
                detail      = "Skald couldn't reach \(host). The Apple engine "
                            + "works offline — switch to it with the panel's "
                            + "offline toggle."
                isRetryable = true

            case .timedOut:
                title       = "Request timed out"
                detail      = "\(host) didn't answer in time."
                isRetryable = true

            case .secureConnectionFailed:
                title       = "Secure connection failed"
                detail      = "The encrypted connection to \(host) was cut short. "
                            + "A VPN or corporate proxy is the usual cause — try "
                            + "again, or exclude \(host) from it."
                isRetryable = true

            case .serverCertificateUntrusted,
                 .serverCertificateHasUnknownRoot,
                 .serverCertificateHasBadDate,
                 .serverCertificateNotYetValid:
                title       = "Certificate not trusted"
                detail      = "macOS didn't trust the certificate \(host) "
                            + "presented. Something is most likely intercepting "
                            + "the connection — a proxy or VPN filter."
                isRetryable = false

            case .networkConnectionLost:
                title       = "Connection lost"
                detail      = "The connection to \(host) dropped mid-request. "
                            + "Usually transient."
                isRetryable = true

            case .cannotFindHost, .dnsLookupFailed, .cannotConnectToHost:
                title       = "Couldn't reach \(host)"
                detail      = "The address didn't resolve, or the connection was "
                            + "refused. Check your network, DNS or VPN."
                isRetryable = true

            default:
                title       = "Network error"
                detail      = "\(err.localizedDescription) (\(host))"
                isRetryable = true
            }
            return
        }

        title          = "Translation failed"
        detail         = error.localizedDescription
        isRetryable    = true
        offersSettings = false
    }
}

/// Shows a `TranslateFailure` as a modal alert. The raw error goes to the
/// log, never to the user.
enum TranslateAlert {

    private enum Action { case retry, settings, dismiss }

    /// - Parameter retry: re-runs the same request. Only wired up when the
    ///   failure is transient; pass nil from flows that can't repeat.
    static func present(_ error: Error,
                        engine: Engine?,
                        retry: (() -> Void)? = nil) {
        let failure = TranslateFailure(error, engine: engine)
        NSLog("Skald: translate error [%@]: %@",
              failure.title, String(describing: error))

        let show = { showAlert(failure, retry: retry) }
        if Thread.isMainThread {
            show()
        } else {
            DispatchQueue.main.async(execute: show)
        }
    }

    private static func showAlert(_ failure: TranslateFailure,
                                  retry: (() -> Void)?) {
        // Running the modal activates us, taking focus away from whatever the
        // user was typing in. Remember it so Retry can hand focus back before
        // the translation gets pasted.
        let previousApp = NSWorkspace.shared.frontmostApplication

        let alert = NSAlert()
        alert.messageText     = failure.title
        alert.informativeText = failure.detail
        alert.alertStyle      = .warning

        // NSAlert lays buttons out right-to-left in the order added, and makes
        // the first one the default, so the most useful action goes first.
        var actions: [Action] = []
        if failure.isRetryable, retry != nil {
            alert.addButton(withTitle: "Retry")
            actions.append(.retry)
        }
        if failure.offersSettings {
            alert.addButton(withTitle: "Open Settings…")
            actions.append(.settings)
        }
        alert.addButton(withTitle: "OK")
        actions.append(.dismiss)
        if alert.buttons.count > 1 {
            alert.buttons.last?.keyEquivalent = "\u{1b}"   // Esc dismisses
        }

        NSApp.activate(ignoringOtherApps: true)
        let index = alert.runModal().rawValue
                  - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        guard actions.indices.contains(index) else { return }

        switch actions[index] {
        case .retry:
            previousApp?.activate()
            // Small cushion so the app is frontmost again before a fast
            // (on-device) translation tries to paste into it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { retry?() }
        case .settings:
            (NSApp.delegate as? AppDelegate)?.openSettings()
        case .dismiss:
            break
        }
    }
}
