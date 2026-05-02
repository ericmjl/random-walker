import Foundation
import RandomWalkerCore
import WatchConnectivity

@MainActor
final class PhoneConnectivityManager: NSObject, ObservableObject {
    @Published private(set) var isReachable: Bool = false

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func sendActiveWalk(_ snapshot: ActiveWalkSnapshot) {
        guard WCSession.isSupported() else { return }
        do {
            let data = try JSONEncoder().encode(snapshot)
            let session = WCSession.default
            let payload = [WatchMessageKey.activeWalk.rawValue: data]
            if session.isReachable {
                session.sendMessage(payload, replyHandler: { _ in }) { _ in
                    try? session.updateApplicationContext(payload)
                }
            } else {
                try session.updateApplicationContext(payload)
            }
        } catch {
            // The phone experience continues even if the watch payload fails.
        }
    }

    func clearWalkOnWatch() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        let payload = [WatchMessageKey.clearWalk.rawValue: Data()]
        try? session.updateApplicationContext(payload)
    }
}

extension PhoneConnectivityManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let reachable = session.isReachable
        Task { @MainActor in
            isReachable = reachable
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            isReachable = reachable
        }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif
}
