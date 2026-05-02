import Foundation
import RandomWalkerCore
import WatchConnectivity

@MainActor
final class WatchWalkCoordinator: NSObject, ObservableObject {
    @Published private(set) var snapshot: ActiveWalkSnapshot?
    @Published private(set) var status: String = "Awaiting a loop from iPhone…"

    func activate() {
        guard WCSession.isSupported() else {
            status = "WatchConnectivity unavailable on this device."
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private func applyActiveWalk(data: Data) {
        do {
            snapshot = try JSONDecoder().decode(ActiveWalkSnapshot.self, from: data)
            status = "Route ready: \(snapshot?.legs.count ?? 0) cues."
        } catch {
            status = "Could not read the route payload."
        }
    }

    private func clearWalk() {
        snapshot = nil
        status = "Route cleared."
    }
}

extension WatchWalkCoordinator: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            switch activationState {
            case .activated:
                status = "Waiting for iPhone…"
            case .inactive:
                status = "Session inactive."
            default:
                status = "Session not activated."
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            handle(context: applicationContext)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            handle(context: message)
        }
    }

    private func handle(context: [String: Any]) {
        if let data = context[WatchMessageKey.activeWalk.rawValue] as? Data {
            applyActiveWalk(data: data)
        }
        if context[WatchMessageKey.clearWalk.rawValue] != nil {
            clearWalk()
        }
    }
}
