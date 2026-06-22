import Foundation
import Network
import Observation

/// Publishes network reachability via `NWPathMonitor`. Drives the offline banner and
/// fires `onReconnect` when connectivity is regained so the sync engine can drain the queue.
@MainActor
@Observable
final class Reachability {
    private(set) var isOnline = true

    /// Invoked when the path transitions from offline to online.
    var onReconnect: (() -> Void)?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.kurtisguy.BabyBuddy.reachability")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.update(online: path.status == .satisfied) }
        }
        monitor.start(queue: queue)
    }

    deinit { monitor.cancel() }

    private func update(online: Bool) {
        let wasOffline = !isOnline
        isOnline = online
        if online && wasOffline { onReconnect?() }
    }
}
