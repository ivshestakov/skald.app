import Foundation

/// One-sentence, human-facing description of a failed translation.
/// The raw error goes to the log, never to the user.
struct TranslateFailure {
    let title: String
    let detail: String
    let isRetryable: Bool
    let offersSettings: Bool

    /// Short single line for the keyboard's status strip.
    var keyboardLine: String { title }

    init(_ error: Error, engine: Engine?) {
        let name = engine?.shortName ?? "The translation service"

        if let err = error as? TranslateError {
            switch err {
            case .missingKey(let eng):
                title = "No API key for \(eng.shortName)"
                detail = "Add one in the Skald app → Settings → Engine."
                isRetryable = false; offersSettings = true
            case .noFullAccess:
                title = "Allow Full Access to translate online"
                detail = "Settings → General → Keyboard → Keyboards → Skald → Allow Full Access. Or switch to the Apple engine."
                isRetryable = false; offersSettings = true
            case .appleUnavailable:
                title = "Apple translation isn't available here"
                detail = "Download the language pack in the Skald app, or pick another engine."
                isRetryable = false; offersSettings = true
            case .network(let code) where code == 401 || code == 403:
                title = "\(name) rejected the API key"
                detail = "Check it in the Skald app → Settings."
                isRetryable = false; offersSettings = true
            case .network(let code) where code == 429:
                title = "\(name) is rate-limiting"
                detail = "Wait a few seconds, then try again."
                isRetryable = true; offersSettings = false
            case .network(let code) where code >= 500:
                title = "\(name) is unavailable"
                detail = "The service is having trouble (HTTP \(code)). Usually temporary."
                isRetryable = true; offersSettings = false
            case .network(let code):
                title = "\(name) returned an error"
                detail = "The request was rejected (HTTP \(code))."
                isRetryable = false; offersSettings = false
            case .parse, .empty:
                title = "Couldn't read the translation"
                detail = "\(name) replied, but Skald couldn't make sense of it."
                isRetryable = true; offersSettings = false
            case .provider(let message):
                title = "\(name) reported an error"
                detail = message
                isRetryable = true; offersSettings = false
            }
            return
        }

        if let err = error as? URLError {
            let host = err.failingURL?.host ?? name
            offersSettings = false
            switch err.code {
            case .notConnectedToInternet:
                title = "No internet connection"
                detail = "Couldn't reach \(host). The Apple engine works offline."
                isRetryable = true
            case .timedOut:
                title = "Request timed out"
                detail = "\(host) didn't answer in time."
                isRetryable = true
            case .networkConnectionLost:
                title = "Connection lost"
                detail = "The connection to \(host) dropped mid-request."
                isRetryable = true
            case .cannotFindHost, .dnsLookupFailed, .cannotConnectToHost:
                title = "Couldn't reach \(host)"
                detail = "Check your network, DNS or VPN."
                isRetryable = true
            default:
                title = "Network error"
                detail = "\(err.localizedDescription) (\(host))"
                isRetryable = true
            }
            return
        }

        title = "Translation failed"
        detail = error.localizedDescription
        isRetryable = true; offersSettings = false
    }
}
