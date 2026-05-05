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

    /// Last walk pushed successfully to the counterpart; replayed when reachability becomes true (sim pairing is flaky).
    private var lastSyncedWalk: ActiveWalkSnapshot?

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
        lastSyncedWalk = nil
        flushWatchOutboundIfReady()
    }

    private func encodedActiveWalkPayload(_ snapshot: ActiveWalkSnapshot) -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            RotatingFileLogger.shared.log("watchConnectivity", "ActiveWalkSnapshot encode failed.")
            return nil
        }
        if data.count >= 62_000 {
            RotatingFileLogger.shared.log(
                "watchConnectivity",
                "Active walk JSON is \(data.count) bytes — may exceed WatchConnectivity application-context limits."
            )
        }
        return [WatchMessageKey.activeWalk.rawValue: data]
    }

    /// Always updates application context so the wearable sees the snapshot even when ``sendMessage`` drops; optionally sends immediately when reachable.
    private func pushActiveWalkToCounterpart(_ snapshot: ActiveWalkSnapshot) {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        guard let payload = encodedActiveWalkPayload(snapshot) else { return }
        lastSyncedWalk = snapshot

        let dataByteCount = (payload[WatchMessageKey.activeWalk.rawValue] as? Data)?.count ?? 0

        do {
            try session.updateApplicationContext(payload)
        } catch {
            RotatingFileLogger.shared.log(
                "watchConnectivity",
                "updateApplicationContext failed (\(error.localizedDescription)); \(dataByteCount) bytes."
            )
        }

        guard session.isReachable else { return }
        // Reply/error handlers must be @Sendable: WCSession invokes them on its own queues, never MainActor.
        session.sendMessage(
            payload,
            replyHandler: { @Sendable _ in },
            errorHandler: { @Sendable sendError in
                RotatingFileLogger.shared.log(
                    "watchConnectivity",
                    "sendMessage(activeWalk) failed — \(sendError.localizedDescription)"
                )
            }
        )
    }

    /// If we already synced a route, pairing flaps can omit delivery — push again when reachable.
    private func replayLastSyncedWalkIfNeeded() {
        guard let snapshot = lastSyncedWalk else { return }
        pushActiveWalkToCounterpart(snapshot)
    }

    private func flushWatchOutboundIfReady() {
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        if let snapshot = pendingWalk {
            pendingWalk = nil
            pushActiveWalkToCounterpart(snapshot)
            return
        }

        if pendingClear {
            let payload: [String: Any] = [WatchMessageKey.clearWalk.rawValue: Data()]
            pendingClear = false
            do {
                try session.updateApplicationContext(payload)
            } catch {
                RotatingFileLogger.shared.log(
                    "watchConnectivity",
                    "updateApplicationContext(clearWalk) failed — \(error.localizedDescription)."
                )
            }
            guard session.isReachable else { return }
            session.sendMessage(
                payload,
                replyHandler: { @Sendable _ in },
                errorHandler: { @Sendable sendError in
                    RotatingFileLogger.shared.log(
                        "watchConnectivity",
                        "sendMessage(clearWalk) failed — \(sendError.localizedDescription)"
                    )
                }
            )
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
                replyHandler: { @Sendable reply in
                    let track: WatchRecordedTrack?
                    if let data = reply[WatchMessageKey.recordedTrack.rawValue] as? Data,
                       let decoded = try? JSONDecoder().decode(WatchRecordedTrack.self, from: data) {
                        track = decoded
                    } else {
                        track = nil
                    }
                    continuation.resume(returning: track)
                },
                errorHandler: { @Sendable _ in
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
            if reachable {
                replayLastSyncedWalkIfNeeded()
            }
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
