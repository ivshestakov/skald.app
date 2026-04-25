import Foundation
import Network

/// Observes network reachability via `NWPathMonitor` and notifies a single
/// optional callback on the main queue. We use this to auto-switch the
/// translation engine to Apple's on-device translator when the machine has
/// no internet, and to flip back when it returns.
///
/// A single shared instance is enough — only the Skald panel is
/// interested. If more observers are ever needed, replace `onChange` with
/// NotificationCenter or a proper subscriber list.
final class NetworkMonitor {

    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "skald.network", qos: .utility)

    /// True when `NWPath.status != .satisfied` — i.e. no route to the internet.
    private(set) var isOffline: Bool = false

    /// Called on the main queue whenever `isOffline` flips. Initial state is
    /// pushed once shortly after first start, so observers don't need to
    /// check `isOffline` separately.
    var onChange: ((Bool) -> Void)?

    private var receivedFirstUpdate = false

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let offline = path.status != .satisfied

            DispatchQueue.main.async {
                let first = !self.receivedFirstUpdate
                let changed = self.isOffline != offline
                self.receivedFirstUpdate = true
                self.isOffline = offline
                if first || changed {
                    self.onChange?(offline)
                }
            }
        }
        monitor.start(queue: queue)
    }
}
