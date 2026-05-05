import CoreLocation
import Foundation

/// Advances the current maneuver from GPS, aligned with phone guidance (two consecutive readings within ``advanceRadiusMeters`` of the maneuver point).
public struct WalkRouteNavigator: Sendable {
    public let legs: [WalkLegHint]
    public private(set) var currentIndex: Int
    private var consecutiveWithinAdvanceRadius: Int
    private let advanceRadiusMeters: CLLocationDistance

    public init(legs: [WalkLegHint], advanceRadiusMeters: CLLocationDistance = 32) {
        self.legs = legs
        self.currentIndex = 0
        self.consecutiveWithinAdvanceRadius = 0
        self.advanceRadiusMeters = advanceRadiusMeters
    }

    /// True when every leg carries maneuver coordinates suitable for GPS step advancement (including on Apple Watch).
    public static func supportsGPSAdvancement(legs: [WalkLegHint]) -> Bool {
        !legs.isEmpty &&
            legs.allSatisfy {
                guard let lat = $0.maneuverLatitude, let lon = $0.maneuverLongitude else { return false }
                return lat.isFinite && lon.isFinite
            }
    }

    public var currentLeg: WalkLegHint? {
        guard currentIndex < legs.count else { return nil }
        return legs[currentIndex]
    }

    public var isComplete: Bool { currentIndex >= legs.count }

    public var upcomingLeg: WalkLegHint? {
        let next = currentIndex + 1
        guard next < legs.count else { return nil }
        return legs[next]
    }

    public mutating func resetProgress() {
        currentIndex = 0
        consecutiveWithinAdvanceRadius = 0
    }

    /// Requires two consecutive readings inside ``advanceRadiusMeters`` so a single jittery GPS point does not skip a step.
    public mutating func ingest(userLocation: CLLocation) {
        guard currentIndex < legs.count else { return }
        let leg = legs[currentIndex]
        guard let latitude = leg.maneuverLatitude,
              let longitude = leg.maneuverLongitude else { return }

        let end = CLLocation(latitude: latitude, longitude: longitude)
        let meters = userLocation.distance(from: end)
        if meters < advanceRadiusMeters {
            consecutiveWithinAdvanceRadius += 1
            if consecutiveWithinAdvanceRadius >= 2 {
                currentIndex += 1
                consecutiveWithinAdvanceRadius = 0
            }
        } else {
            consecutiveWithinAdvanceRadius = 0
        }
    }

    public func distanceToCurrentManeuver(from userLocation: CLLocation) -> CLLocationDistance? {
        guard let leg = currentLeg,
              let latitude = leg.maneuverLatitude,
              let longitude = leg.maneuverLongitude else { return nil }

        let end = CLLocation(latitude: latitude, longitude: longitude)
        return userLocation.distance(from: end)
    }

    public func maneuverCoordinate(forStepIndex stepIndex: Int) -> CLLocationCoordinate2D? {
        guard stepIndex >= 0,
              stepIndex < legs.count,
              let latitude = legs[stepIndex].maneuverLatitude,
              let longitude = legs[stepIndex].maneuverLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    public func instructionDisplayString(forStepIndex stepIndex: Int) -> String? {
        guard stepIndex >= 0, stepIndex < legs.count else { return nil }
        let raw = legs[stepIndex].title.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? "Continue" : raw
    }

    /// Bearing from ``from`` degrees clockwise from north to ``to`` (0° = north).
    public static func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> CLLocationDirection {
        let lat1 = from.latitude * .pi / 180
        let lon1 = from.longitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let lon2 = to.longitude * .pi / 180
        let dLon = lon2 - lon1
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let radians = atan2(y, x)
        let degrees = radians * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }
}
