import AppKit
import SwiftUI
import Translation

/// On-device translation via Apple's `Translation` framework (macOS 15.0+).
///
/// The framework is SwiftUI-first: the only way to obtain a `TranslationSession`
/// is via the `.translationTask(_:_:)` view modifier. We bridge that back to
/// our AppKit app by parking a one-shot `NSHostingController` in an
/// off-screen, essentially-invisible window for the duration of each request.
///
/// First use of a new (source, target) pair triggers a system dialog asking
/// the user to download the language model (~50–100 MB). After that, calls
/// are fully offline and text never leaves the device.
@available(macOS 15.0, *)
enum AppleTranslator {

    @MainActor
    static func translate(_ text: String,
                          source: Language,
                          target: Language,
                          completion: @escaping (Result<String, Error>) -> Void) {

        let sourceLang = Locale.Language(identifier: source.rawValue)
        let targetLang = Locale.Language(identifier: target.rawValue)

        // Hold a strong reference to the hosting window for the lifetime
        // of the request so SwiftUI doesn't tear it down mid-flight.
        var hosting: NSWindow?

        let bridge = AppleTranslationBridge(
            text: text,
            source: sourceLang,
            target: targetLang
        ) { result in
            completion(result)
            hosting?.orderOut(nil)
            hosting = nil
        }

        let hostingController = NSHostingController(
            rootView: AppleTranslationBridgeView(bridge: bridge)
        )

        let window = NSWindow(
            contentRect: NSRect(x: -10_000, y: -10_000, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.hasShadow = false
        // Fully transparent would get the window collapsed by the WS; a
        // nearly-zero alpha keeps it "visible" to AppKit so SwiftUI actually
        // schedules the translationTask.
        window.alphaValue = 0.001
        window.orderFrontRegardless()
        hosting = window
    }
}

@available(macOS 15.0, *)
@MainActor
private final class AppleTranslationBridge: ObservableObject {

    @Published var configuration: TranslationSession.Configuration?
    let text: String

    private let completion: (Result<String, Error>) -> Void
    private var finished = false

    init(text: String,
         source: Locale.Language,
         target: Locale.Language,
         completion: @escaping (Result<String, Error>) -> Void) {
        self.text = text
        self.completion = completion

        // Set the configuration one runloop tick later, so the SwiftUI view
        // has time to attach the `translationTask` modifier before we change
        // the observed value.
        DispatchQueue.main.async { [weak self] in
            self?.configuration = TranslationSession.Configuration(
                source: source,
                target: target
            )
        }
    }

    func finish(_ result: Result<String, Error>) {
        guard !finished else { return }
        finished = true
        completion(result)
    }
}

@available(macOS 15.0, *)
private struct AppleTranslationBridgeView: View {
    @ObservedObject var bridge: AppleTranslationBridge

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .translationTask(bridge.configuration) { session in
                do {
                    let response = try await session.translate(bridge.text)
                    bridge.finish(.success(response.targetText))
                } catch {
                    bridge.finish(.failure(error))
                }
            }
    }
}
