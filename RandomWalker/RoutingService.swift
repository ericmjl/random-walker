import Foundation
import MapKit
import RandomWalkerCore

/// Builds a single stitched walking route using Apple's MapKit directions.
enum RoutingServiceError: LocalizedError, Equatable {
    case emptyBlueprint
    case directionsFailed(String?)
    case emptyRoute

    var errorDescription: String? {
        switch self {
        case .emptyBlueprint:
            return "The planner did not produce any intermediate stops."
        case let .directionsFailed(message):
            return message ?? "Directions request failed."
        case .emptyRoute:
            return "Apple Maps returned an empty walking route."
        }
    }
}

struct RoutedWalk: Sendable {
    let id: UUID
    let coordinates: [CLLocationCoordinate2D]
    let legs: [RoutedLeg]
    let distanceMeters: CLLocationDistance
    let expectedTravelTime: TimeInterval
}

/// MapKit turn steps converted to plain values for Swift concurrency and watch export.
struct RoutedStep: Sendable {
    let instructions: String
    let distance: CLLocationDistance
    let expectedTravelTime: TimeInterval
    /// Approximate maneuver location (end of the step polyline); used for turn-by-turn progress.
    let maneuverCoordinate: CLLocationCoordinate2D
}

struct RoutedLeg: Sendable {
    let steps: [RoutedStep]
    let distance: CLLocationDistance
    let expectedTravelTime: TimeInterval
}

enum RoutingService {
    /// Fuses walking directions between each stop in the blueprint, including the return to center.
    static func routeWalkingLoop(
        blueprint: LoopWalkBlueprint
    ) async throws -> RoutedWalk {
        let stops = blueprint.visitSequenceCoordinates
        guard stops.count >= 3 else {
            throw RoutingServiceError.emptyBlueprint
        }

        var coordinates: [CLLocationCoordinate2D] = []
        var legs: [RoutedLeg] = []
        var totalDistance: CLLocationDistance = 0
        var totalDuration: TimeInterval = 0
        let routeIdentifier = UUID()

        for index in 0 ..< (stops.count - 1) {
            let source = stops[index].coordinate
            let destination = stops[index + 1].coordinate
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: source))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
            request.transportType = .walking
            request.requestsAlternateRoutes = false

            let calculator = MKDirections(request: request)
            let response: MKDirections.Response
            do {
                response = try await calculator.calculate()
            } catch {
                throw RoutingServiceError.directionsFailed(error.localizedDescription)
            }
            guard let route = response.routes.first else {
                throw RoutingServiceError.emptyRoute
            }

            let coords = route.polyline.toCoordinates()
            if coordinates.isEmpty {
                coordinates.append(contentsOf: coords)
            } else if let first = coords.first, let last = coordinates.last, last.isNearlyEqual(to: first) {
                coordinates.append(contentsOf: coords.dropFirst())
            } else {
                coordinates.append(contentsOf: coords.dropFirst())
            }

            totalDistance += route.distance
            totalDuration += route.expectedTravelTime
            let legDistance = route.distance
            let legDuration = route.expectedTravelTime
            let routedSteps = route.steps.map { step in
                let stepDuration: TimeInterval
                if legDistance > 0 {
                    stepDuration = legDuration * (step.distance / legDistance)
                } else {
                    stepDuration = 0
                }
                let maneuverCoordinate = step.polyline.lastCoordinate(fallback: destination)
                return RoutedStep(
                    instructions: step.instructions,
                    distance: step.distance,
                    expectedTravelTime: stepDuration,
                    maneuverCoordinate: maneuverCoordinate
                )
            }
            legs.append(RoutedLeg(steps: routedSteps, distance: route.distance, expectedTravelTime: route.expectedTravelTime))
        }

        return RoutedWalk(
            id: routeIdentifier,
            coordinates: coordinates,
            legs: legs,
            distanceMeters: totalDistance,
            expectedTravelTime: totalDuration
        )
    }

    /// Rebuilds directions from the user's **current** position through the remaining blueprint visits.
    ///
    /// Use after a deviation so guidance follows fresh walking legs toward the not-yet-visited waypoints,
    /// then continues to the loop center as in the original plan.
    static func routeWalkingResume(
        from start: CLLocationCoordinate2D,
        visitSequence: [GeodesicWaypoint],
        nextVisitIndex: Int
    ) async throws -> RoutedWalk {
        guard nextVisitIndex < visitSequence.count else {
            throw RoutingServiceError.emptyBlueprint
        }

        let tail = visitSequence[nextVisitIndex...].map(\.coordinate)
        let chain = [start] + tail
        guard chain.count >= 2 else {
            throw RoutingServiceError.emptyBlueprint
        }

        var coordinates: [CLLocationCoordinate2D] = []
        var legs: [RoutedLeg] = []
        var totalDistance: CLLocationDistance = 0
        var totalDuration: TimeInterval = 0
        let routeIdentifier = UUID()

        for index in 0 ..< (chain.count - 1) {
            let source = chain[index]
            let destination = chain[index + 1]
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: source))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
            request.transportType = .walking
            request.requestsAlternateRoutes = false

            let calculator = MKDirections(request: request)
            let response: MKDirections.Response
            do {
                response = try await calculator.calculate()
            } catch {
                throw RoutingServiceError.directionsFailed(error.localizedDescription)
            }
            guard let route = response.routes.first else {
                throw RoutingServiceError.emptyRoute
            }

            let coords = route.polyline.toCoordinates()
            if coordinates.isEmpty {
                coordinates.append(contentsOf: coords)
            } else if let first = coords.first, let last = coordinates.last, last.isNearlyEqual(to: first) {
                coordinates.append(contentsOf: coords.dropFirst())
            } else {
                coordinates.append(contentsOf: coords.dropFirst())
            }

            totalDistance += route.distance
            totalDuration += route.expectedTravelTime
            let legDistance = route.distance
            let legDuration = route.expectedTravelTime
            let routedSteps = route.steps.map { step in
                let stepDuration: TimeInterval
                if legDistance > 0 {
                    stepDuration = legDuration * (step.distance / legDistance)
                } else {
                    stepDuration = 0
                }
                let maneuverCoordinate = step.polyline.lastCoordinate(fallback: destination)
                return RoutedStep(
                    instructions: step.instructions,
                    distance: step.distance,
                    expectedTravelTime: stepDuration,
                    maneuverCoordinate: maneuverCoordinate
                )
            }
            legs.append(RoutedLeg(steps: routedSteps, distance: route.distance, expectedTravelTime: route.expectedTravelTime))
        }

        return RoutedWalk(
            id: routeIdentifier,
            coordinates: coordinates,
            legs: legs,
            distanceMeters: totalDistance,
            expectedTravelTime: totalDuration
        )
    }
}

private extension MKPolyline {
    func toCoordinates() -> [CLLocationCoordinate2D] {
        var extracted: [CLLocationCoordinate2D] = []
        let pointCount = self.pointCount
        let ptr = self.points()
        extracted.reserveCapacity(pointCount)
        for index in 0 ..< pointCount {
            let mapPoint = ptr[index]
            extracted.append(mapPoint.coordinate)
        }
        return extracted
    }

    func lastCoordinate(fallback: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let coords = toCoordinates()
        if let last = coords.last {
            return last
        }
        return fallback
    }
}

private extension CLLocationCoordinate2D {
    func isNearlyEqual(to other: CLLocationCoordinate2D, epsilon: Double = 0.000_01) -> Bool {
        abs(latitude - other.latitude) < epsilon && abs(longitude - other.longitude) < epsilon
    }
}
