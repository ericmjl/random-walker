import CoreLocation
import Dispatch
import Foundation
import RandomWalkerCore
import WatchConnectivity
import WatchKit

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

/// Encodes cue content only (excluding per-transfer random `WalkLegHint.id`) so identical WatchConnectivity replays do not reset progress mid-walk.
private struct WalkLegCueSignature: Codable, Equatable {
    var title: String
    var distanceMeters: Double
    var expectedTravelTime: TimeInterval
    var maneuverLatitude: Double?
    var maneuverLongitude: Double?
}

@MainActor
final class WatchWalkCoordinator: NSObject, ObservableObject {
    @Published private(set) var snapshot: ActiveWalkSnapshot?
    @Published private(set) var status: String = "Awaiting a loop from iPhone…"
    @Published private(set) var isRecordingGPS: Bool = false
    /// Live step index driven by GPS (same advancement rules as iPhone navigation).
    @Published private(set) var watchNavigationStepIndex: Int = 0
    @Published private(set) var distanceToCurrentManeuverMeters: CLLocationDistance?
    /// True when this session’s payload carries maneuver coordinates and the watch advances steps automatically.
    @Published private(set) var isWatchGPSGuidanceActive: Bool = false
    /// True once every cue in the synced payload has been consumed on the Watch.
    @Published private(set) var isSyncedRouteCuesFinishedOnWatch: Bool = false

    private let locationManager = CLLocationManager()

    private var recordingSessionId: UUID?
    private var recordingRouteId: UUID?
    private var recordingStartedAt: Date?
    private var samples: [GeodesicWaypoint] = []

    /// Mirrored navigator for turn-by-turn (when ``isWatchGPSGuidanceActive`` is true).
    private var routeNavigator: WalkRouteNavigator?
    /// Fingerprint of synced cue payloads for the active session (excluding random leg IDs).
    private var lastSyncedNavigationCueSignatureData: Data?

    private static let minSampleSeparationMeters: CLLocationDistance = 8
    /// Tighter filter while cue-by-cue GPS guidance runs so paired consecutive hits near maneuver points land faster.
    private static let navigationDistanceFilterMeters: CLLocationDistance = 5

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
                if isWatchGPSGuidanceActive {
                    status = "Navigation on Watch • recording path."
                } else if !next.legs.isEmpty {
                    status =
                        "Recording • use Back/Next to browse cues—update iPhone/watch app for GPS turns."
                } else {
                    status = "Recording walk path for iPhone…"
                }
            } else {
                stopRecordingTransferAndResetState(sendToPhone: true)
                status = "Route ready: \(next.legs.count) cues."
            }
        } catch {
            status = "Could not read the route payload."
        }
    }

    private func rebuildWatchRouteNavigator(legs: [WalkLegHint], sessionStarted: Bool) {
        guard sessionStarted, WalkRouteNavigator.supportsGPSAdvancement(legs: legs) else {
            routeNavigator = nil
            isWatchGPSGuidanceActive = false
            watchNavigationStepIndex = 0
            distanceToCurrentManeuverMeters = nil
            isSyncedRouteCuesFinishedOnWatch = false
            updateLocationDistanceFilter()
            return
        }
        routeNavigator = WalkRouteNavigator(legs: legs)
        isWatchGPSGuidanceActive = true
        watchNavigationStepIndex = 0
        distanceToCurrentManeuverMeters = nil
        isSyncedRouteCuesFinishedOnWatch = false
        updateLocationDistanceFilter()
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
            lastSyncedNavigationCueSignatureData = cueSignatureData(legs: snapshot.legs)
            rebuildWatchRouteNavigator(legs: snapshot.legs, sessionStarted: true)
        } else {
            recordingRouteId = snapshot.routeId
            guard let nextSig = cueSignatureData(legs: snapshot.legs) else {
                lastSyncedNavigationCueSignatureData = nil
                rebuildWatchRouteNavigator(legs: snapshot.legs, sessionStarted: true)
                isRecordingGPS = true
                startLocationUpdatesIfAuthorized()
                return
            }
            if nextSig != lastSyncedNavigationCueSignatureData {
                lastSyncedNavigationCueSignatureData = nextSig
                rebuildWatchRouteNavigator(legs: snapshot.legs, sessionStarted: true)
            }
        }

        isRecordingGPS = true
        startLocationUpdatesIfAuthorized()
    }

    private func cueSignatureData(legs: [WalkLegHint]) -> Data? {
        let cues = legs.map {
            WalkLegCueSignature(
                title: $0.title,
                distanceMeters: $0.distanceMeters,
                expectedTravelTime: $0.expectedTravelTime,
                maneuverLatitude: $0.maneuverLatitude,
                maneuverLongitude: $0.maneuverLongitude
            )
        }
        return try? JSONEncoder().encode(cues)
    }

    private func startLocationUpdatesIfAuthorized() {
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
        routeNavigator = nil
        isWatchGPSGuidanceActive = false
        watchNavigationStepIndex = 0
        distanceToCurrentManeuverMeters = nil
        isSyncedRouteCuesFinishedOnWatch = false
        lastSyncedNavigationCueSignatureData = nil
        updateLocationDistanceFilter()
        locationManager.stopUpdatingLocation()
    }

    private func updateLocationDistanceFilter() {
        if isRecordingGPS, isWatchGPSGuidanceActive {
            locationManager.distanceFilter = Self.navigationDistanceFilterMeters
        } else if isRecordingGPS {
            locationManager.distanceFilter = Self.minSampleSeparationMeters
        } else {
            locationManager.distanceFilter = Self.minSampleSeparationMeters
        }
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

    private func ingestGPSGuidance(location: CLLocation) {
        guard isWatchGPSGuidanceActive else {
            distanceToCurrentManeuverMeters = nil
            return
        }
        guard var navigator = routeNavigator else {
            distanceToCurrentManeuverMeters = nil
            return
        }
        let priorIndex = navigator.currentIndex
        navigator.ingest(userLocation: location)
        routeNavigator = navigator
        watchNavigationStepIndex = navigator.currentIndex
        distanceToCurrentManeuverMeters = navigator.distanceToCurrentManeuver(from: location)

        if navigator.currentIndex > priorIndex {
            WKInterfaceDevice.current().play(.directionUp)
        }

        if navigator.isComplete {
            isSyncedRouteCuesFinishedOnWatch = true
            distanceToCurrentManeuverMeters = nil
            status =
                "Last cue on Watch done. If you still have turns, check iPhone—or you may be near the end."
        }
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
        if let uuidString = message[WatchMessageKey.requestRecordingFlush.rawValue] as? String,
           let uuid = UUID(uuidString: uuidString)
        {
            struct FlushEnvelope: @unchecked Sendable {
                let payload: [String: Any]
            }

            let replySnapshot: [String: Any]
            if Thread.isMainThread {
                // Avoid blocking the main queue waiting for MainActor work (deadlock otherwise).
                let envelope = MainActor.assumeIsolated {
                    FlushEnvelope(payload: buildFlushReply(sessionId: uuid))
                }
                replySnapshot = envelope.payload
            } else {
                // Flush replies capture MainActor coordinator state while honoring WatchConnectivity’s
                // expectation that `replyHandler` fire quickly.
                let holder = FlushReplyHolder([:])
                let semaphore = DispatchSemaphore(value: 0)
                Task { @MainActor in
                    let reply = self.buildFlushReply(sessionId: uuid)
                    holder.reply = reply
                    semaphore.signal()
                }
                semaphore.wait()
                replySnapshot = holder.reply
            }
            replyHandler(replySnapshot)
            return
        }

        // Reachable counterpart uses `sendMessage` for snapshots; acknowledging immediately avoids
        // system termination of this extension before the reply is delivered.
        replyHandler([:])
        let walkData = message[WatchMessageKey.activeWalk.rawValue] as? Data
        let shouldClear = message[WatchMessageKey.clearWalk.rawValue] != nil
        Task { @MainActor in
            if let walkData {
                self.applyActiveWalk(data: walkData)
            }
            if shouldClear {
                self.clearWalkUI()
            }
        }
    }
}

/// Holds a Connectivity reply dictionary across a semaphore boundary (`[String: Any]` is not `Sendable`).
private final class FlushReplyHolder: @unchecked Sendable {
    var reply: [String: Any]
    init(_ reply: [String: Any]) { self.reply = reply }
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
            self.ingestGPSGuidance(location: loc)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.status = "Location error: \(error.localizedDescription)"
        }
    }
}
