import Foundation
import RandomWalkerCore
import WatchConnectivity

@MainActor
final class PhoneConnectivityManager: NSObject, ObservableObject {
    @Published private(set) var isReachable: Bool = false

    /// Called when a track arrives via `transferUserInfo` (e.g. watch flushed after **Discard**).
    var onWatchRecordedTrack: ((WatchRecordedTrack) -> Void)?

    /// Latest route to push once ``WCSession`` finishes activating (``updateApplicationContext`` throws if not ready).
    private var pendingWalk: ActiveWalkSnapshot?
    private var pendingClear: Bool = false

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func sendActiveWalk(_ snapshot: ActiveWalkSnapshot) {
        guard WCSession.isSupported() else { return }
        pendingWalk = snapshot
        pendingClear = false
        flushWatchOutboundIfReady()
    }

    func clearWalkOnWatch() {
        guard WCSession.isSupported() else { return }
        pendingWalk = nil
        pendingClear = true
        flushWatchOutboundIfReady()
    }

    private func flushWatchOutboundIfReady() {
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        if let snapshot = pendingWalk {
            guard let data = try? JSONEncoder().encode(snapshot) else {
                pendingWalk = nil
                return
            }
            let payload: [String: Any] = [WatchMessageKey.activeWalk.rawValue: data]
            pendingWalk = nil
            if session.isReachable {
                session.sendMessage(payload, replyHandler: { _ in }, errorHandler: { _ in
                    try? session.updateApplicationContext(payload)
                })
            } else {
                try? session.updateApplicationContext(payload)
            }
            return
        }

        if pendingClear {
            let payload: [String: Any] = [WatchMessageKey.clearWalk.rawValue: Data()]
            pendingClear = false
            try? session.updateApplicationContext(payload)
            if session.isReachable {
                session.sendMessage(payload, replyHandler: { _ in }, errorHandler: { _ in })
            }
        }
    }

    /// Asks the watch to package the in-progress recording when it is reachable (e.g. before saving history).
    func requestWatchRecording(for sessionId: UUID) async -> WatchRecordedTrack? {
        guard WCSession.isSupported() else { return nil }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return nil }
        return await withCheckedContinuation { continuation in
            session.sendMessage(
                [WatchMessageKey.requestRecordingFlush.rawValue: sessionId.uuidString],
                replyHandler: { reply in
                    guard let data = reply[WatchMessageKey.recordedTrack.rawValue] as? Data,
                          let track = try? JSONDecoder().decode(WatchRecordedTrack.self, from: data)
                    else {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(returning: track)
                },
                errorHandler: { _ in
                    continuation.resume(returning: nil)
                }
            )
        }
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
            if activationState == .activated {
                flushWatchOutboundIfReady()
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            isReachable = reachable
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let payload = userInfo[WatchMessageKey.recordedTrack.rawValue] as? Data
        Task { @MainActor in
            guard let payload,
                  let track = try? JSONDecoder().decode(WatchRecordedTrack.self, from: payload)
            else {
                return
            }
            onWatchRecordedTrack?(track)
        }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif
}
