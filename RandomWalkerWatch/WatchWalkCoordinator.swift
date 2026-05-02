import CoreLocation
import Foundation
import RandomWalkerCore
import WatchConnectivity

/// Values extracted from ``WCSession`` application context on the delegate queue (``Sendable`` for Swift 6).
private struct PhoneApplicationContextPayload: Sendable {
    var isEmpty: Bool
    var activeWalkData: Data?
    var shouldClear: Bool

    init(_ applicationContext: [String: Any]) {
        isEmpty = applicationContext.isEmpty
        activeWalkData = applicationContext[WatchMessageKey.activeWalk.rawValue] as? Data
        shouldClear = applicationContext[WatchMessageKey.clearWalk.rawValue] != nil
    }
}

private final class WatchMessageReplyBox: @unchecked Sendable {
    let handler: ([String: Any]) -> Void

    init(_ handler: @escaping ([String: Any]) -> Void) {
        self.handler = handler
    }

    func callAsFunction(_ reply: [String: Any]) {
        handler(reply)
    }
}

@MainActor
final class WatchWalkCoordinator: NSObject, ObservableObject {
    @Published private(set) var snapshot: ActiveWalkSnapshot?
    @Published private(set) var status: String = "Awaiting a loop from iPhone…"
    @Published private(set) var isRecordingGPS: Bool = false

    private let locationManager = CLLocationManager()
    private var recordingSessionId: UUID?
    private var recordingRouteId: UUID?
    private var recordingStartedAt: Date?
    private var samples: [GeodesicWaypoint] = []

    private static let minSampleSeparationMeters: CLLocationDistance = 8

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = Self.minSampleSeparationMeters
    }

    func activate() {
        guard WCSession.isSupported() else {
            status = "WatchConnectivity unavailable on this device."
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Applies the last application context from the paired iPhone (activation snapshot or delegate callback).
    private func applyPhoneContextPayload(_ payload: PhoneApplicationContextPayload) {
        if payload.isEmpty {
            status = "Waiting for iPhone…"
        }
        if let walkData = payload.activeWalkData {
            applyActiveWalk(data: walkData)
        }
        if payload.shouldClear {
            clearWalkUI()
        }
    }

    private func applyActiveWalk(data: Data) {
        do {
            let next = try JSONDecoder().decode(ActiveWalkSnapshot.self, from: data)
            snapshot = next

            if let sessionId = next.navigationSessionId {
                beginOrContinueRecording(snapshot: next, sessionId: sessionId)
                status =
                    "Recording path • \(next.legs.count) cues. Open the app on iPhone for the full map."
            } else {
                stopRecordingTransferAndResetState(sendToPhone: true)
                status = "Route ready: \(next.legs.count) cues."
            }
        } catch {
            status = "Could not read the route payload."
        }
    }

    private func beginOrContinueRecording(snapshot: ActiveWalkSnapshot, sessionId: UUID) {
        if recordingSessionId != sessionId {
            if recordingSessionId != nil {
                transferCurrentRecordingToPhone()
            }
            recordingSessionId = sessionId
            recordingRouteId = snapshot.routeId
            recordingStartedAt = snapshot.recordingStartedAt ?? .now
            samples.removeAll(keepingCapacity: true)
        } else {
            recordingRouteId = snapshot.routeId
        }

        isRecordingGPS = true
        let auth = locationManager.authorizationStatus
        if auth == .authorizedWhenInUse || auth == .authorizedAlways {
            locationManager.startUpdatingLocation()
        } else {
            locationManager.requestWhenInUseAuthorization()
        }
    }

    private func stopRecordingTransferAndResetState(sendToPhone: Bool) {
        if sendToPhone {
            transferCurrentRecordingToPhone()
        }
        recordingSessionId = nil
        recordingRouteId = nil
        recordingStartedAt = nil
        samples.removeAll(keepingCapacity: true)
        isRecordingGPS = false
        locationManager.stopUpdatingLocation()
    }

    private func transferCurrentRecordingToPhone() {
        guard let track = buildTrack(endedAt: .now) else { return }
        transferTrack(track)
    }

    private func buildTrack(endedAt: Date) -> WatchRecordedTrack? {
        guard let sessionId = recordingSessionId,
              let routeId = recordingRouteId,
              let started = recordingStartedAt,
              !samples.isEmpty
        else {
            return nil
        }
        return WatchRecordedTrack(
            routeId: routeId,
            navigationSessionId: sessionId,
            startedAt: started,
            endedAt: endedAt,
            samples: samples
        )
    }

    private func transferTrack(_ track: WatchRecordedTrack) {
        guard let data = try? JSONEncoder().encode(track) else { return }
        guard WCSession.default.activationState == .activated else { return }
        let payload: [String: Any] = [WatchMessageKey.recordedTrack.rawValue: data]
        WCSession.default.transferUserInfo(payload)
    }

    private func clearWalkUI() {
        stopRecordingTransferAndResetState(sendToPhone: true)
        snapshot = nil
        status = "Route cleared."
    }

    /// Builds the flush reply dictionary for `requestRecordingFlush` (must run on the main actor).
    private func buildFlushReply(sessionId: UUID) -> [String: Any] {
        guard sessionId == recordingSessionId,
              let track = buildTrack(endedAt: .now),
              let data = try? JSONEncoder().encode(track)
        else {
            return [:]
        }
        stopRecordingTransferAndResetState(sendToPhone: false)
        return [WatchMessageKey.recordedTrack.rawValue: data]
    }

    private func appendSampleIfNeeded(_ coordinate: CLLocationCoordinate2D) {
        guard recordingSessionId != nil else { return }
        if let last = samples.last {
            let previous = CLLocation(latitude: last.latitude, longitude: last.longitude)
            let next = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            guard previous.distance(from: next) >= Self.minSampleSeparationMeters else { return }
        }
        samples.append(GeodesicWaypoint(coordinate))
    }
}

extension WatchWalkCoordinator: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let contextPayload = PhoneApplicationContextPayload(session.receivedApplicationContext)
        Task { @MainActor in
            switch activationState {
            case .activated:
                // The counterpart may have called ``updateApplicationContext`` before our session
                // finished activating; that payload is exposed here and is not always replayed
                // through ``didReceiveApplicationContext`` (common on Simulator and cold launch).
                applyPhoneContextPayload(contextPayload)
            case .inactive:
                status = "Session inactive."
            default:
                status = "Session not activated."
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let contextPayload = PhoneApplicationContextPayload(applicationContext)
        Task { @MainActor in
            applyPhoneContextPayload(contextPayload)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        let replyBox = WatchMessageReplyBox(replyHandler)
        if let uuidString = message[WatchMessageKey.requestRecordingFlush.rawValue] as? String,
           let uuid = UUID(uuidString: uuidString) {
            Task { @MainActor in
                let reply = self.buildFlushReply(sessionId: uuid)
                replyBox(reply)
            }
            return
        }

        let walkData = message[WatchMessageKey.activeWalk.rawValue] as? Data
        let shouldClear = message[WatchMessageKey.clearWalk.rawValue] != nil
        Task { @MainActor in
            if let walkData {
                self.applyActiveWalk(data: walkData)
            }
            if shouldClear {
                self.clearWalkUI()
            }
            replyBox([:])
        }
    }
}

extension WatchWalkCoordinator: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            if self.isRecordingGPS, status == .authorizedWhenInUse || status == .authorizedAlways {
                self.locationManager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            self.appendSampleIfNeeded(loc.coordinate)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.status = "Location error: \(error.localizedDescription)"
        }
    }
}
