import Foundation
import RandomWalkerCore

extension RoutedWalk {
    enum WalkHintExportLimits {
        /// WatchConnectivity payloads stay small; cues beyond this rely on finishing the remainder on iPhone.
        static let maxHintsForWatch = 200
    }

    /// Flattens MapKit walking steps into cues for connectivity and navigation.
    ///
    /// - Parameter maxHints: Caps list length when sending to Watch; pass `nil` for every MapKit step on iPhone navigation.
    func flattenedWalkLegHints(maxHints: Int? = nil) -> [WalkLegHint] {
        let all = legs.flatMap(\.steps)
        let capped = maxHints.map { Array(all.prefix($0)) } ?? Array(all)
        return capped.map { step in
            let dist = step.distance.isFinite ? step.distance : 0
            let travel = step.expectedTravelTime.isFinite && step.expectedTravelTime >= 0 ? step.expectedTravelTime : 0
            let lat = step.maneuverCoordinate.latitude
            let lon = step.maneuverCoordinate.longitude
            let mLat = lat.isFinite ? lat : nil
            let mLon = lon.isFinite ? lon : nil
            return WalkLegHint(
                title: Self.sanitized(step.instructions),
                distanceMeters: dist,
                expectedTravelTime: travel,
                maneuverLatitude: mLat,
                maneuverLongitude: mLon
            )
        }
    }

    func makeWatchSnapshot(
        startedAt: Date,
        navigationSessionId: UUID? = nil,
        recordingStartedAt: Date? = nil
    ) -> ActiveWalkSnapshot {
        let hints = flattenedWalkLegHints(maxHints: WalkHintExportLimits.maxHintsForWatch)
        let total = distanceMeters.isFinite ? distanceMeters : 0
        let duration =
            expectedTravelTime.isFinite && expectedTravelTime >= 0 ? expectedTravelTime : 0
        return ActiveWalkSnapshot(
            routeId: id,
            startedAt: startedAt,
            legs: hints,
            totalDistanceMeters: total,
            expectedDurationSeconds: duration,
            navigationSessionId: navigationSessionId,
            recordingStartedAt: recordingStartedAt
        )
    }

    static func sanitized(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Continue" : trimmed
    }
}
