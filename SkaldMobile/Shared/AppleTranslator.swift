import SwiftUI
import Translation
import UIKit

/// On-device translation via Apple's `Translation` framework (iOS 18+).
///
/// The framework only hands out a `TranslationSession` through the SwiftUI
/// `.translationTask` modifier, so each request parks a tiny hosting
/// controller inside a host view for its duration. Callers must register a
/// host view first (`AppleTranslator.hostView`) — the app does it from its
/// root view, the keyboard from its input view. Without one the engine
/// reports `appleUnavailable` instead of hanging.
@MainActor
enum AppleTranslator {

    /// A view that stays in the hierarchy while translations run.
    static weak var hostView: UIView?

    private static var inFlight: [UIHostingController<BridgeView>] = []

    static func translate(_ text: String, source: Language, target: Language) async throws -> String {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            guard let host = hostView, host.window != nil else {
                cont.resume(throwing: TranslateError.appleUnavailable); return
            }
            let bridge = Bridge(text: text,
                                source: Locale.Language(identifier: source.rawValue),
                                target: Locale.Language(identifier: target.rawValue))
            var controller: UIHostingController<BridgeView>?
            bridge.completion = { result in
                cont.resume(with: result)
                if let c = controller {
                    c.view.removeFromSuperview()
                    inFlight.removeAll { $0 === c }
                }
                controller = nil
            }
            let hc = UIHostingController(rootView: BridgeView(bridge: bridge))
            hc.view.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
            hc.view.alpha = 0.01
            hc.view.isUserInteractionEnabled = false
            host.addSubview(hc.view)
            controller = hc
            inFlight.append(hc)

            // Safety net: the framework may never call back when a language
            // pack is missing and the download sheet can't be shown (e.g. in
            // a keyboard extension).
            DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
                bridge.finish(.failure(TranslateError.appleUnavailable))
            }
        }
    }

    @MainActor
    final class Bridge: ObservableObject {
        @Published var configuration: TranslationSession.Configuration?
        let text: String
        var completion: ((Result<String, Error>) -> Void)?
        private var finished = false

        init(text: String, source: Locale.Language, target: Locale.Language) {
            self.text = text
            DispatchQueue.main.async { [weak self] in
                self?.configuration = TranslationSession.Configuration(source: source, target: target)
            }
        }

        func finish(_ result: Result<String, Error>) {
            guard !finished else { return }
            finished = true
            completion?(result)
            completion = nil
        }
    }

    struct BridgeView: View {
        @ObservedObject var bridge: Bridge
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
}
