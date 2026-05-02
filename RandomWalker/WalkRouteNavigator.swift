import CoreLocation
import Foundation

/// Linear list of walking maneuvers derived from a solved `RoutedWalk`, used for in-app guidance.
struct RoutedNavigationStep: Sendable {
    let instruction: String
    let distance: CLLocationDistance
    let expectedTravelTime: TimeInterval
    let maneuverCoordinate: CLLocationCoordinate2D
}

/// Advances the current maneuver from GPS, similar in spirit to Apple Maps turn-by-turn (simplified).
struct WalkRouteNavigator: Sendable {
    let steps: [RoutedNavigationStep]
    private(set) var currentIndex: Int
    private var consecutiveWithinAdvanceRadius: Int

    private let advanceRadiusMeters: CLLocationDistance

    init(steps: [RoutedNavigationStep], advanceRadiusMeters: CLLocationDistance = 32) {
        self.steps = steps
        self.currentIndex = 0
        self.consecutiveWithinAdvanceRadius = 0
        self.advanceRadiusMeters = advanceRadiusMeters
    }

    var currentStep: RoutedNavigationStep? {
        guard currentIndex < steps.count else { return nil }
        return steps[currentIndex]
    }

    var isComplete: Bool { currentIndex >= steps.count }

    var upcomingStep: RoutedNavigationStep? {
        let next = currentIndex + 1
        guard next < steps.count else { return nil }
        return steps[next]
    }

    mutating func resetProgress() {
        currentIndex = 0
        consecutiveWithinAdvanceRadius = 0
    }

    /// Call on location updates while navigating. Uses consecutive readings inside the advance radius to damp GPS noise.
    mutating func ingest(userLocation: CLLocation) {
        guard currentIndex < steps.count else { return }
        let step = steps[currentIndex]
        let end = CLLocation(
            latitude: step.maneuverCoordinate.latitude,
            longitude: step.maneuverCoordinate.longitude
        )
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

    func distanceToCurrentManeuver(from userLocation: CLLocation) -> CLLocationDistance? {
        guard let step = currentStep else { return nil }
        let end = CLLocation(
            latitude: step.maneuverCoordinate.latitude,
            longitude: step.maneuverCoordinate.longitude
        )
        return userLocation.distance(from: end)
    }

    static func flattenedSteps(from walk: RoutedWalk) -> [RoutedNavigationStep] {
        walk.legs.flatMap { leg in
            leg.steps.map { step in
                RoutedNavigationStep(
                    instruction: step.instructions,
                    distance: step.distance,
                    expectedTravelTime: step.expectedTravelTime,
                    maneuverCoordinate: step.maneuverCoordinate
                )
            }
        }
    }

    static func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> CLLocationDirection {
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
